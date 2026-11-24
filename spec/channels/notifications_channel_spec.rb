# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationsChannel do
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }

  def signed_stream(*streamables)
    Turbo::StreamsChannel.signed_stream_name(streamables)
  end

  it "subscribes the owner of an active membership to its private stream" do
    stub_connection current_user: membership.user

    subscribe signed_stream_name: signed_stream(membership, :notifications)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(Turbo::StreamsChannel.send(:stream_name_from, [membership, :notifications]))
  end

  it "rejects another user's stream even with a valid signature" do
    stub_connection current_user: create(:user)

    subscribe signed_stream_name: signed_stream(membership, :notifications)

    expect(subscription).to be_rejected
  end

  it "rejects streams of deactivated memberships" do
    in_tenant(organization) { membership.update!(status: "deactivated") }
    stub_connection current_user: membership.user

    subscribe signed_stream_name: signed_stream(membership, :notifications)

    expect(subscription).to be_rejected
  end

  it "rejects tampered stream names" do
    stub_connection current_user: membership.user

    subscribe signed_stream_name: "forjado--assinatura"

    expect(subscription).to be_rejected
  end
end
