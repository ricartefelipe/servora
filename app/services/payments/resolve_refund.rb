# frozen_string_literal: true

module Payments
  # Human resolution of a refund that needs attention:
  #
  # * "confirm": verified at the provider (or executed manually) — accepted;
  # * "retry": verified that the provider did NOT process it — sent again.
  class ResolveRefund
    ACTIONS = %w[confirm retry].freeze

    def initialize(refund:, action:, actor:)
      @refund = refund
      @action = action.to_s
      @actor = actor
    end

    def call
      raise Servora::RuleViolation, "Ação inválida." unless ACTIONS.include?(@action)

      ActiveRecord::Base.transaction(requires_new: true) do
        @refund.lock!
        raise Servora::RuleViolation, "Este estorno não precisa de verificação." unless @refund.needs_attention?

        @action == "confirm" ? confirm : retry_submission
        AuditEvent.record!(action: "payment_refund.#{@action}", auditable: @refund, changes: { status: @refund.status })
        @refund
      end
    end

    private

    def confirm
      @refund.update!(status: "accepted", resolved_at: Time.current, resolved_by_membership_id: @actor.id)
    end

    def retry_submission
      if @refund.status == "manual"
        raise Servora::RuleViolation,
          "Estornos de pagamentos manuais são executados pela equipe financeira."
      end

      @refund.update!(status: "pending", last_error: nil, resolved_by_membership_id: @actor.id)
      Outbox::Publisher.publish!(event_type: "payment_refund.requested", aggregate: @refund,
        dedup_key: "payment_refund.requested:#{@refund.id}:#{@refund.attempts}")
    end
  end
end
