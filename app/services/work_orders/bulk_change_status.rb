# frozen_string_literal: true

module WorkOrders
  # Moves several work orders to the same status through WorkOrders::ChangeStatus.
  #
  # Each order is loaded on its own (strict loading flags rows loaded as a set),
  # checked with the caller's authorization callable and changed inside its own
  # savepoint, so a refused or failing order never rolls back the others. Ids
  # outside the given scope (another organization, or orders the person cannot
  # see) are ignored. One audit event lists what changed and what was refused.
  class BulkChangeStatus
    MAX_ORDERS = 100
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    class TooMany < Servora::RuleViolation; end
    class NothingSelected < Servora::RuleViolation; end

    Failure = Data.define(:work_order, :reason)
    Result = Data.define(:to, :updated, :failed) do
      def any_failed? = failed.any?
    end

    # Short pt-BR reasons shown next to each refused order.
    REASONS = {
      forbidden: "sem permissão",
      transition: "situação não permite",
      stale: "alterada por outra pessoa",
      invalid: "não foi possível alterar"
    }.freeze

    def initialize(scope:, ids:, to:, actor:, reason: nil, authorize: ->(_work_order) { true })
      @scope = scope
      @ids = Array(ids).map(&:to_s).grep(UUID_FORMAT).uniq
      @requested = Array(ids).compact_blank.uniq.size
      @to = to.to_s
      @actor = actor
      @reason = reason.to_s.strip.presence
      @authorize = authorize
    end

    def call
      validate!
      updated = []
      failed = []
      @scope.where(id: @ids).order(:number).pluck(:id).each do |id|
        work_order = @scope.includes(:assignments).find(id)
        outcome = change(work_order)
        outcome == :ok ? updated << work_order : failed << Failure.new(work_order:, reason: REASONS.fetch(outcome))
      end
      audit(updated, failed)
      Result.new(to: @to, updated:, failed:)
    end

    private

    def validate!
      raise NothingSelected, "Selecione ao menos uma ordem." if @ids.empty?
      raise TooMany, "Selecione no máximo #{MAX_ORDERS} ordens por vez." if @requested > MAX_ORDERS
      raise Transition::InvalidTransition, "Escolha uma situação válida." unless ChangeStatus::ALLOWED_TARGETS.include?(@to)
      raise ChangeStatus::ReasonRequired, "Informe o motivo da espera." if reason_missing?
    end

    def reason_missing? = ChangeStatus::REASON_REQUIRED.include?(@to) && @reason.nil?

    def change(work_order)
      return :forbidden unless @authorize.call(work_order)
      return :transition unless States.allowed?(work_order.status, @to)

      ChangeStatus.new(work_order:, to: @to, actor: @actor, reason: @reason).call
      :ok
    rescue Transition::InvalidTransition
      :transition
    rescue ActiveRecord::StaleObjectError
      :stale
    rescue Servora::RuleViolation, ActiveRecord::RecordInvalid
      :invalid
    end

    def audit(updated, failed)
      return if updated.empty?

      AuditEvent.record!(action: "work_order.bulk_status_changed",
        changes: { status: LABELS[@to], reason: @reason, updated_numbers: updated.map(&:number),
                   refused_numbers: failed.map { |failure| failure.work_order.number } }.compact_blank,
        metadata: { work_order_ids: updated.map(&:id) })
    end
  end
end
