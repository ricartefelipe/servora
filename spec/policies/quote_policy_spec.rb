# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotePolicy do
  let(:scenario) { build_quote_scenario }
  let(:organization) { scenario[:organization] }
  let(:quote) { create_quote(scenario) }

  def context_for(role)
    membership = create(:membership, role:, organization:)
    PolicyContext.new(user: membership.user, membership:)
  end

  def policy(role, record = quote)
    in_tenant(organization) { described_class.new(context_for(role), Quote.includes(:current_version).find(record.id)) }
  end

  it "allows editing drafts only to roles that manage quotes" do
    expect(policy("attendant").edit_draft?).to be(true)
    expect(policy("finance").edit_draft?).to be(false)
    expect(policy("finance").show?).to be(true)
    expect(policy("technician").show?).to be(false)
  end

  it "moves permissions along the lifecycle" do
    send_quote(scenario, quote)

    attendant = policy("attendant")
    expect(attendant.edit_draft?).to be(false)
    expect(attendant.new_version?).to be(true)
    expect(attendant.register_decision?).to be(true)
    expect(attendant.cancel?).to be(true)
    expect(attendant.view_costs?).to be(false)
    expect(policy("auditor").view_costs?).to be(true)
  end

  it "scopes quotes to roles with quote access" do
    quote
    resolved = in_tenant(organization) { described_class::Scope.new(context_for("technician"), Quote.all).resolve.to_a }

    expect(resolved).to be_empty
  end
end
