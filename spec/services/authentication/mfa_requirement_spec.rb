# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::MfaRequirement do
  let(:organization) { build(:organization, mfa_required_for_privileged: true) }
  let(:joined_at) { Time.zone.parse("2026-11-01 10:00") }

  def requirement(role:, mfa: false, now: joined_at)
    user = build(:user, otp_required_for_login: mfa)
    membership = build(:membership, role:, organization:, user:, created_at: joined_at)
    described_class.new(membership:, user:, now:)
  end

  it "requires MFA from privileged roles only" do
    expect(requirement(role: "owner").required?).to be(true)
    expect(requirement(role: "finance").required?).to be(true)
    expect(requirement(role: "technician").required?).to be(false)
    expect(requirement(role: "owner", mfa: true).required?).to be(false)
  end

  it "allows a grace period before blocking" do
    expect(requirement(role: "admin", now: joined_at + 6.days)).to be_pending
    expect(requirement(role: "admin", now: joined_at + 7.days)).to be_blocking
  end

  it "does not apply when the organization disables the rule" do
    organization.mfa_required_for_privileged = false

    expect(requirement(role: "owner", now: joined_at + 30.days).blocking?).to be(false)
  end
end
