# frozen_string_literal: true

module Payments
  # Reconciles a charge with the provider (polling fallback for lost
  # confirmations and for charges whose submission outcome is unknown).
  class SyncCharge
    def initialize(organization_id:, charge_id:)
      @organization_id = organization_id
      @charge_id = charge_id
    end

    def call
      charge, integration = load
      return unless charge
      return SubmitCharge.new(organization_id: @organization_id, charge_id: @charge_id).call if charge.status == "unknown"

      remote = Gateways.for(integration).find_charge(charge)
      apply(remote)
    end

    private

    def tenant(&) = Servora::Tenancy.with_organization(@organization_id, &)

    def load
      tenant do
        charge = PaymentCharge.find_by(id: @charge_id)
        next nil unless charge && %w[submitted unknown].include?(charge.status)

        [charge, PaymentIntegration.for(@organization_id)]
      end
    end

    def apply(remote)
      if remote&.status == "confirmed"
        ConfirmCharge.new(organization_id: @organization_id, charge_id: @charge_id, paid_at: remote.paid_at).call
      else
        tenant do
          charge = PaymentCharge.lock.find(@charge_id)
          canceled = remote&.status == "canceled" && charge.status == "submitted"
          charge.update!(last_synced_at: Time.current, status: canceled ? "canceled" : charge.status)
        end
      end
    end
  end
end
