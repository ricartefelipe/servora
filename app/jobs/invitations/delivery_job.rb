# frozen_string_literal: true

module Invitations
  class DeliveryJob < ApplicationJob
    queue_as :mailers

    retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, attempts: 5, wait: :polynomially_longer

    def perform(organization_id, invitation_id)
      Invitations::Deliver.new(organization_id:, invitation_id:).call
    end
  end
end
