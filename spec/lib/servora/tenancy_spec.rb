# frozen_string_literal: true

require "rails_helper"

RSpec.describe Servora::Tenancy do
  let(:organization_a) { create(:organization) }
  let(:organization_b) { create(:organization) }

  it "exposes only the rows of the organization in context" do
    create(:membership, organization: organization_a)
    create(:membership, organization: organization_b)

    in_tenant(organization_a) do
      expect(Membership.distinct.pluck(:organization_id)).to eq([organization_a.id])
    end
  end

  it "hides every tenant row when no context is present" do
    create(:membership, organization: organization_a)

    expect(Membership.count).to eq(0)
    expect(Organization.count).to eq(0)
  end

  it "restores the previous context after a nested block" do
    described_class.with_organization(organization_a.id) do
      described_class.with_organization(organization_b.id) do
        expect(described_class.current_organization_id).to eq(organization_b.id)
      end
      expect(described_class.current_organization_id).to eq(organization_a.id)
    end
    expect(described_class.current_organization_id).to be_nil
  end

  it "reverts the context when the block raises" do
    described_class.with_organization(organization_a.id) do
      expect do
        described_class.with_organization(organization_b.id) { raise ArgumentError, "falha" }
      end.to raise_error(ArgumentError)
      expect(described_class.current_organization_id).to eq(organization_a.id)
    end
  end

  it "does not reuse cached query results across contexts" do
    create(:membership, organization: organization_a)

    ActiveRecord::Base.cache do
      count_a = in_tenant(organization_a) { Membership.count }
      count_b = in_tenant(organization_b) { Membership.count }

      expect([count_a, count_b]).to eq([1, 0])
    end
  end

  it "rejects missing or malformed identifiers" do
    expect { described_class.with_context { nil } }.to raise_error(described_class::MissingContext)
    expect { described_class.with_organization(nil) { nil } }.to raise_error(described_class::MissingContext)
    expect { described_class.with_organization("1; DROP TABLE users") { nil } }
      .to raise_error(described_class::InvalidIdentifier)
  end

  it "keeps the user context so members can list their own organizations" do
    membership = create(:membership, organization: organization_a)
    create(:membership, organization: organization_b)

    described_class.with_context(user_id: membership.user_id) do
      expect(Organization.pluck(:id)).to eq([organization_a.id])
      expect(Membership.pluck(:id)).to eq([membership.id])
    end
  end
end
