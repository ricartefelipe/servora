# frozen_string_literal: true

class InvitationsController < TenantController
  rate_limit to: 30, within: 1.hour, only: :create, name: "invitation-issue",
    with: -> { redirect_to members_path, alert: "Limite de convites atingido. Tente novamente mais tarde." }

  def create
    @invitation = current_organization.invitations.new(invitation_params)
    authorize @invitation
    Invitations::Issue.new(inviter: current_membership, email: @invitation.email, role: @invitation.role).call
    redirect_to members_path, notice: "Convite enviado para #{@invitation.email}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to members_path, alert: e.record.errors.full_messages.to_sentence
  rescue Servora::RuleViolation => e
    redirect_to members_path, alert: e.message
  end

  def destroy
    invitation = current_organization.invitations.find(params.expect(:id))
    authorize invitation
    Invitations::Revoke.new(invitation:).call
    redirect_to members_path, notice: "Convite revogado."
  rescue Servora::RuleViolation => e
    redirect_to members_path, alert: e.message
  end

  private

  def invitation_params
    params.expect(invitation: %i[email role])
  end
end
