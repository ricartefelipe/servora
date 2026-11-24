# frozen_string_literal: true

require "rails_helper"

RSpec.describe Outbox::Publisher do
  let(:organization) { create(:organization) }
  let(:invitation) { create(:invitation, organization:) }

  it "records the event in the caller's transaction" do
    in_tenant(organization) do
      described_class.publish!(event_type: "invitation.issued", aggregate: invitation, payload: { "role" => "technician" })
    end

    event = outbox_events(organization).sole
    expect(event).to have_attributes(event_type: "invitation.issued", aggregate_id: invitation.id, status: "pending",
      payload: { "role" => "technician" })
  end

  it "disappears together with a rolled back business transaction" do
    in_tenant(organization) do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.publish!(event_type: "invitation.issued", aggregate: invitation)
        raise ActiveRecord::Rollback
      end
    end

    expect(outbox_events(organization)).to be_empty
  end

  it "ignores a second event with the same deduplication key" do
    ids = in_tenant(organization) do
      Array.new(2) { described_class.publish!(event_type: "invitation.accepted", aggregate: invitation, dedup_key: "k-1") }
    end

    expect(ids.first).to be_present
    expect(ids.last).to be_nil
    expect(outbox_events(organization).size).to eq(1)
  end

  it "cannot publish for another organization" do
    other = create(:organization)

    expect do
      in_tenant(other) { described_class.publish!(event_type: "invitation.issued", aggregate: invitation) }
    end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end
end
