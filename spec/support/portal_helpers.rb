# frozen_string_literal: true

# Enters the customer portal through the real e-mailed access link.
module PortalHelpers
  def portal_token_for(contact, organization = contact.organization)
    grant = in_tenant(organization) { Portal::IssueGrant.new(contact:, purpose: "portal").call }
    Portal::DeliverGrant.new(organization_id: organization.id, grant_id: grant.id).call
    ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/portal/acesso/([\w-]+)}, 1]
  end

  def enter_portal(contact)
    post portal_access_path(portal_token_for(contact))
  end
end

RSpec.configure do |config|
  config.include PortalHelpers, type: :request
end
