# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Team management" do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }
  let(:admin) { create(:membership, :admin, organization:) }
  let(:technician) { create(:membership, :technician, organization:) }

  describe "GET /equipe" do
    it "lists members for roles that can see the team" do
      technician
      sign_in_as(admin)

      get members_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(technician.user.name)
    end

    it "is forbidden for technicians" do
      sign_in_as(technician)

      get members_path

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Acesso negado")
    end
  end

  describe "PATCH /equipe/:id" do
    it "updates the role with strong parameters" do
      sign_in_as(admin)

      patch member_path(technician),
        params: { membership: { role: "coordinator", status: "deactivated", organization_id: SecureRandom.uuid } }

      membership = in_tenant(organization) { technician.reload }
      expect(membership).to have_attributes(role: "coordinator", status: "active", organization_id: organization.id)
    end

    it "does not let an admin grant the owner role" do
      sign_in_as(admin)

      patch member_path(technician), params: { membership: { role: "owner" } }

      expect(response).to have_http_status(:forbidden)
      expect(in_tenant(organization) { technician.reload.role }).to eq("technician")
    end

    it "denies changes to roles that can only view the team" do
      sign_in_as(create(:membership, :coordinator, organization:))

      patch member_path(technician), params: { membership: { job_title: "Técnico II", hourly_cost: "999" } }

      expect(response).to have_http_status(:forbidden)
      expect(in_tenant(organization) { technician.reload }).to have_attributes(job_title: nil, hourly_cost: nil)
    end
  end

  describe "deactivation" do
    it "removes access and keeps the last owner protected" do
      sign_in_as(owner)

      patch deactivate_member_path(technician)
      expect(in_tenant(organization) { technician.reload.status }).to eq("deactivated")

      patch deactivate_member_path(owner)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "invitations" do
    it "issues and revokes invitations" do
      sign_in_as(owner)

      post team_invitations_path, params: { invitation: { email: "novo@servora.test", role: "attendant" } }
      invitation = in_tenant(organization) { Invitation.find_by!(email: "novo@servora.test") }

      expect { run_dispatcher }.to have_enqueued_job(Invitations::DeliveryJob).with(organization.id, invitation.id)

      delete team_invitation_path(invitation)

      expect(in_tenant(organization) { invitation.reload.state }).to eq(:revoked)
    end

    it "accepts an invitation end to end with a POST only" do
      token = Invitation.generate_token
      create(:invitation, organization:, invited_by: owner, email: "aceita@servora.test", role: "attendant", token:)
      invitee = create(:user, email: "aceita@servora.test")

      get invitation_path(token)
      expect(response.body).to include("Convite para #{organization.name}")

      sign_in invitee
      post invitation_path(token)

      expect(response).to redirect_to(dashboard_path)
      expect(in_tenant(organization) { Membership.find_by(user: invitee)&.role }).to eq("attendant")
    end

    it "shows a generic page for unknown tokens" do
      get invitation_path("desconhecido")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "settings and audit" do
    it "lets admins update settings and records the change in the audit trail" do
      sign_in_as(admin)

      patch settings_path, params: { organization: { travel_buffer_minutes: 45, document: "11.222.333/0001-81" } }
      get audit_events_path

      expect(in_tenant(organization) { organization.reload.travel_buffer_minutes }).to eq(45)
      expect(response.body).to include("organization.updated")
    end

    it "rejects invalid settings with feedback" do
      sign_in_as(admin)

      patch settings_path, params: { organization: { travel_buffer_minutes: 9999 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Revise os campos destacados")
    end

    it "hides the audit trail from operational roles" do
      sign_in_as(create(:membership, :attendant, organization:))

      get audit_events_path

      expect(response).to have_http_status(:forbidden)
    end
  end
end
