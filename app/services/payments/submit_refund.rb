# frozen_string_literal: true

module Payments
  # Sends a pending refund to the provider, outside any transaction.
  #
  # * not delivered (connection refused, open timeout, 429): stays pending and
  #   the job retries — nothing reached the provider;
  # * ambiguous (read timeout, 5xx): becomes "unknown" and is NOT retried,
  #   because a refund may not be idempotent at the provider; a person
  #   verifies it (Payments::ResolveRefund);
  # * refused: "failed" with the provider's message.
  class SubmitRefund
    def initialize(organization_id:, refund_id:)
      @organization_id = organization_id
      @refund_id = refund_id
    end

    def call
      refund, charge, integration = claim
      return unless refund

      remote = Gateways.for(integration).refund_charge(charge, refund)
      finish("accepted", external_id: remote.external_id, submitted_at: Time.current)
    rescue Gateways::Errors::Rejected => e
      finish("failed", last_error: e.message.truncate(500))
    rescue Gateways::Errors::AmbiguousResponse => e
      finish("unknown", last_error: e.message.truncate(500))
    end

    private

    def tenant(&) = Servora::Tenancy.with_organization(@organization_id, &)

    def claim
      tenant do
        refund = PaymentRefund.lock.find_by(id: @refund_id)
        next nil unless refund&.status == "pending"

        refund.update!(attempts: refund.attempts + 1)
        payment = Payment.find(refund.payment_id)
        [refund, PaymentCharge.find(payment.payment_charge_id), PaymentIntegration.for(@organization_id)]
      end
    end

    def finish(status, **attributes)
      tenant do
        refund = PaymentRefund.lock.find(@refund_id)
        next unless refund.status == "pending"

        refund.update!(status:, **attributes)
        AuditEvent.record!(action: "payment_refund.#{status}", auditable: refund,
          organization: Organization.find(@organization_id), changes: attributes.slice(:last_error, :external_id))
      end
    end
  end
end
