# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication" do
  let(:password) { "senha-segura-de-teste" }
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, :coordinator, organization:) }
  let(:user) { membership.user }

  def sign_in_with(email:, password:)
    post user_session_path, params: { user: { email:, password: } }
  end

  it "signs in and opens the only organization automatically" do
    sign_in_with(email: user.email, password:)
    follow_redirect!

    expect(response).to redirect_to(dashboard_path)
    follow_redirect!
    expect(response.body).to include(organization.name)
    expect(user.user_sessions.active.count).to eq(1)
  end

  it "uses the same message for unknown e-mails and wrong passwords" do
    sign_in_with(email: "ninguem@servora.test", password:)
    unknown = flash[:alert]
    sign_in_with(email: user.email, password: "senha-errada")

    expect(flash[:alert]).to eq(unknown)
    expect(unknown).to eq("E-mail ou senha inválidos.")
  end

  it "locks the account after repeated failures" do
    5.times { sign_in_with(email: user.email, password: "errada") }

    expect(user.reload.access_locked?).to be(true)
    sign_in_with(email: user.email, password:)
    expect(user.user_sessions.count).to eq(0)
  end

  it "rate limits sign in attempts by client" do
    11.times { sign_in_with(email: "x@servora.test", password: "y") }

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to include("Muitas tentativas")
  end

  it "rejects unconfirmed accounts" do
    unconfirmed = create(:user, :unconfirmed)

    sign_in_with(email: unconfirmed.email, password:)

    expect(unconfirmed.user_sessions.count).to eq(0)
  end

  describe "two-step sign in" do
    let(:user) { create(:user, :with_mfa) }

    before { create(:membership, organization:, user:) }

    it "requires the TOTP code after the password" do
      sign_in_with(email: user.email, password:)
      expect(response).to redirect_to(user_two_factor_challenge_path)
      expect(user.user_sessions.count).to eq(0)

      post user_two_factor_challenge_path, params: { otp_attempt: user.reload.current_otp }

      expect(response).to redirect_to(organizations_path)
      expect(user.user_sessions.active.count).to eq(1)
    end

    it "rejects a wrong code and counts the attempt" do
      sign_in_with(email: user.email, password:)
      post user_two_factor_challenge_path, params: { otp_attempt: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.failed_attempts).to eq(1)
    end

    it "accepts each backup code only once" do
      codes = user.generate_otp_backup_codes!
      user.save!

      sign_in_with(email: user.email, password:)
      post user_two_factor_challenge_path, params: { otp_attempt: codes.first }
      expect(response).to redirect_to(organizations_path)

      delete destroy_user_session_path
      sign_in_with(email: user.email, password:)
      post user_two_factor_challenge_path, params: { otp_attempt: codes.first }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not reach the second step with a wrong password" do
      sign_in_with(email: user.email, password: "errada")

      expect(response).to redirect_to(new_user_session_path)
      get user_two_factor_challenge_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "server-side sessions" do
    it "ends a session immediately when it is revoked elsewhere" do
      sign_in_as(membership)
      get dashboard_path
      expect(response).to have_http_status(:ok)

      user.user_sessions.active.each { |session| session.revoke!(reason: "test") }
      get dashboard_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "revokes the server session on logout" do
      sign_in_as(membership)
      delete destroy_user_session_path

      expect(user.user_sessions.active.count).to eq(0)
      expect(user.user_sessions.last.revoke_reason).to eq("logout")
    end

    it "lets the user end other sessions" do
      other = user.user_sessions.create!(last_seen_at: Time.current)
      sign_in_as(membership)

      delete others_account_sessions_path

      expect(other.reload).not_to be_active
      expect(user.user_sessions.active.count).to eq(1)
    end
  end

  describe "e-mail confirmation" do
    it "does not confirm on GET and confirms on POST" do
      unconfirmed = create(:user, :unconfirmed)
      token = unconfirmed.confirmation_token

      get user_confirmation_path(confirmation_token: token)
      expect(unconfirmed.reload.confirmed?).to be(false)

      post confirm_user_confirmation_path, params: { confirmation_token: token }
      expect(unconfirmed.reload.confirmed?).to be(true)
    end
  end
end
