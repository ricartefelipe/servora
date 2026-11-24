# frozen_string_literal: true

module Sla
  # Periodic SLA alert scan, organization by organization.
  class ScanJob < ApplicationJob
    queue_as :default

    def perform
      Servora::ActiveOrganizations.each_id do |organization_id|
        Servora::Tenancy.with_organization(organization_id) { Sla::Scan.new.call }
      end
    end
  end
end
