# frozen_string_literal: true

module Payments
  # Sends a pending charge to the provider. Three short steps:
  #
  # 1. claim (transaction, row lock): only pending/unknown charges proceed and
  #    the attempt counter is incremented;
  # 2. provider call outside any transaction: after an earlier attempt, the
  #    charge is first looked up by external reference, so a lost response
  #    never produces a duplicate charge;
  # 3. record (transaction, row lock) the outcome. A charge canceled meanwhile
  #    is canceled at the provider too.
  #
  # Unavailable and ambiguous outcomes re-raise so the job retries later.
  class SubmitCharge
    def initialize(organization_id:, charge_id:)
      @organization_id = organization_id
      @charge_id = charge_id
    end

    def call
      charge, integration, customer = claim
      return unless charge

      remote = contact_provider(charge, integration, customer)
      record(remote)
    rescue Gateways::Errors::Rejected => e
      record_failure(e.message)
    rescue Gateways::Errors::AmbiguousResponse => e
      record_unknown(e.message)
      raise
    end

    private

    def tenant(&) = Servora::Tenancy.with_organization(@organization_id, &)

    def claim
      tenant do
        charge = PaymentCharge.lock.find_by(id: @charge_id)
        next nil unless charge && %w[pending unknown].include?(charge.status)

        charge.update!(attempts: charge.attempts + 1)
        receivable = Receivable.find(charge.receivable_id)
        [charge, PaymentIntegration.for(@organization_id), Customer.find(receivable.customer_id)]
      end
    end

    def contact_provider(charge, integration, customer)
      gateway = Gateways.for(integration)
      found = gateway.find_charge(charge) if charge.attempts > 1 || charge.status == "unknown"
      found || gateway.create_charge(charge, customer)
    end

    def record(remote)
      confirmed = tenant do
        charge = PaymentCharge.lock.find(@charge_id)
        next cancel_remotely(charge, remote) if charge.status == "canceled"

        charge.update!(status: "submitted", external_id: remote.external_id, payment_url: remote.payment_url,
          submitted_at: charge.submitted_at || Time.current, last_synced_at: Time.current, last_error: nil)
        log(charge, "charge_submitted", external_id: remote.external_id)
        remote.status == "confirmed" ? charge : nil
      end
      ConfirmCharge.new(organization_id: @organization_id, charge_id: @charge_id, paid_at: remote.paid_at).call if confirmed
    end

    def cancel_remotely(charge, remote)
      charge.update!(external_id: remote.external_id)
      Outbox::Publisher.publish!(event_type: "payment_charge.canceled", aggregate: charge,
        dedup_key: "payment_charge.canceled:#{charge.id}")
      nil
    end

    def record_unknown(message)
      tenant do
        charge = PaymentCharge.lock.find(@charge_id)
        next unless charge.active?

        charge.update!(status: "unknown", last_error: message.truncate(500))
        log(charge, "charge_unknown", error: message)
      end
    end

    def record_failure(message)
      tenant do
        charge = PaymentCharge.lock.find(@charge_id)
        next unless charge.active?

        charge.update!(status: "failed", last_error: message.truncate(500))
        log(charge, "charge_failed", error: message)
      end
    end

    def log(charge, kind, **details)
      FinancialEvent.record!(receivable: Receivable.find(charge.receivable_id), kind:, amount: charge.amount, details:)
    end
  end
end
