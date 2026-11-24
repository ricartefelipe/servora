# frozen_string_literal: true

require "net/protocol"

module Portal
  class GrantDeliveryJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, attempts: 5, wait: :polynomially_longer

    def perform(organization_id, grant_id)
      Portal::DeliverGrant.new(organization_id:, grant_id:).call
    end
  end
end
