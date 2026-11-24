# frozen_string_literal: true

module Contracts
  # Activation, suspension, resumption and termination.
  #
  # * suspending and ending require a reason;
  # * ending deactivates the preventive plans;
  # * resuming skips the calendar occurrences that fell during the suspension
  #   (they are not owed), so the scheduler does not catch them up.
  class ChangeStatus
    TIMESTAMPS = { "active" => :activated_at, "suspended" => :suspended_at, "ended" => :ended_at }.freeze

    def initialize(contract:, to:, actor:, reason: nil, today: Time.zone.today)
      @contract = contract
      @to = to.to_s
      @actor = actor
      @reason = reason.to_s.strip.presence
      @today = today
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @contract.lock!
        from = @contract.status
        transition!(from)
        apply_side_effects(from)
        AuditEvent.record!(action: "contract.#{@to}", auditable: @contract, changes: { from:, to: @to, reason: @reason })
        @contract
      end
    end

    private

    def transition!(from)
      unless States.allowed?(from, @to)
        raise Errors::Invalid, "Não é possível passar de #{Contract::STATUSES[from]} para #{Contract::STATUSES.fetch(@to, @to)}."
      end
      raise Errors::Invalid, "Informe o motivo." if %w[suspended ended].include?(@to) && @reason.nil?

      @contract.update!(status: @to, TIMESTAMPS.fetch(@to) => Time.current, status_reason: @reason || @contract.status_reason)
    end

    def apply_side_effects(from)
      plans = MaintenancePlan.where(contract_id: @contract.id)
      plans.update_all(active: false, updated_at: Time.current) if @to == "ended" # rubocop:disable Rails/SkipsModelValidations -- bulk deactivation
      skip_suspended_period(plans.active.lock.to_a) if from == "suspended" && @to == "active"
    end

    def skip_suspended_period(plans)
      plans.reject(&:after_completion?).each do |plan|
        sequence = plan.next_sequence
        sequence += 1 while plan.schedule.due_on([sequence, plan.anchor_sequence].max) < @today
        plan.update!(last_sequence: sequence - 1) if sequence > plan.next_sequence
      end
    end
  end
end
