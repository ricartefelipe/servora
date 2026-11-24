# frozen_string_literal: true

module Payments
  # Cancels at the provider a charge already canceled in Servora.
  class CancelRemoteCharge
    def initialize(organization_id:, charge_id:)
      @organization_id = organization_id
      @charge_id = charge_id
    end

    def call
      charge, integration = Servora::Tenancy.with_organization(@organization_id) do
        found = PaymentCharge.find_by(id: @charge_id)
        next nil unless found&.status == "canceled" && found.external_id.present?

        [found, PaymentIntegration.for(@organization_id)]
      end
      return unless charge

      Gateways.for(integration).cancel_charge(charge)
    end
  end
end
