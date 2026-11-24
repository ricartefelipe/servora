# frozen_string_literal: true

module Quotes
  # Daily expiry of quote versions, organization by organization, each in its
  # own tenant context.
  class ExpireJob < ApplicationJob
    queue_as :default

    def perform
      Servora::ActiveOrganizations.each_id do |organization_id|
        Servora::Tenancy.with_organization(organization_id) do
          Quotes::ExpireDue.new(organization: Organization.find(organization_id)).call
        end
      end
    end
  end
end
