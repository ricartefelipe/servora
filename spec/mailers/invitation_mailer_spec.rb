# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvitationMailer do
  it "sends the personal link with organization and role" do
    organization = create(:organization, name: "Clima Oeste")
    invitation = create(:invitation, organization:, role: "finance")
    in_tenant(organization) { invitation = Invitation.includes(:organization, invited_by: :user).find(invitation.id) }

    mail = described_class.invite(invitation:, token: "abc123")

    expect(mail.subject).to eq("Convite para a equipe Clima Oeste no Servora")
    expect(mail.to).to eq([invitation.email])
    expect(mail.html_part.body.to_s).to include("Financeiro", "/convites/abc123")
  end
end
