# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portal do
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }

  def delivered_token
    ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{/portal/acesso/([\w-]+)}, 1]
  end

  it "notifies approvers when a quote is sent, idempotently per event" do
    send_quote(scenario, create_quote(scenario))

    run_dispatcher
    grants = in_tenant(organization) { PortalAccessGrant.where(contact_id: scenario[:approver].id).to_a }
    event = outbox_events(organization).find { |e| e.event_type == "quote.sent" }
    in_tenant(organization) { OutboxEvent.where(id: event.id).update_all(status: "pending", available_at: 1.second.ago) }
    run_dispatcher

    expect(grants.size).to eq(1)
    expect(in_tenant(organization) { PortalAccessGrant.count }).to eq(1)
    expect(Portal::GrantDeliveryJob).to have_been_enqueued.with(organization.id, grants.first.id).at_least(:once)
  end

  it "exchanges a delivered link once for a restricted session" do
    grant = in_tenant(organization) { Portal::IssueGrant.new(contact: scenario[:approver], purpose: "portal").call }
    Portal::DeliverGrant.new(organization_id: organization.id, grant_id: grant.id).call
    token = delivered_token

    result = Portal::ExchangeGrant.new(token:, ip: "198.51.100.7", user_agent: "x").call

    expect(result.session.contact_id).to eq(scenario[:approver].id)
    expect(Portal::Authenticate.organization_for(result.session_token)).to eq(organization.id)
    expect { Portal::ExchangeGrant.new(token:, ip: nil, user_agent: nil).call }
      .to raise_error(Portal::ExchangeGrant::InvalidGrant, /já foi utilizado/)
  end

  it "refuses contacts without portal access and revoked sessions" do
    follower = create(:customer_contact, customer: scenario[:customer], portal_enabled: false)
    expect { in_tenant(organization) { Portal::IssueGrant.new(contact: follower, purpose: "portal").call } }
      .to raise_error(Portal::IssueGrant::NotEligible)

    grant = in_tenant(organization) { Portal::IssueGrant.new(contact: scenario[:approver], purpose: "portal").call }
    Portal::DeliverGrant.new(organization_id: organization.id, grant_id: grant.id).call
    result = Portal::ExchangeGrant.new(token: delivered_token, ip: nil, user_agent: nil).call
    in_tenant(organization) { result.session.update!(revoked_at: Time.current) }

    expect(Portal::Authenticate.organization_for(result.session_token)).to be_nil
  end
end
