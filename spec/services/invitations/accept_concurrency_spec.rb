# frozen_string_literal: true

require "rails_helper"

# Two browsers accept the same invitation at the same time. The row lock makes
# the second transaction wait for the first one and then observe the invitation
# as already used: exactly one membership is created.
RSpec.describe Invitations::Accept, :committed do
  it "is single-use under concurrent acceptance" do
    organization = create(:organization)
    owner = create(:membership, organization:)
    invitee = create(:user, email: "concorrente@servora.test")
    token = Invitation.generate_token
    create(:invitation, organization:, invited_by: owner, email: invitee.email, token:)

    results = ConcurrencyHelpers.run_in_parallel(2) do
      described_class.new(token:, user: invitee).call
      :accepted
    rescue described_class::InvalidInvitation, ActiveRecord::RecordNotUnique
      :rejected
    end

    expect(results.sort).to eq(%i[accepted rejected])
    expect(in_tenant(organization) { Membership.where(user: invitee).count }).to eq(1)
  end
end
