# frozen_string_literal: true

class InvitationMailer < ApplicationMailer
  def invite(invitation:, token:)
    @invitation = invitation
    @organization = invitation.organization
    @inviter_name = invitation.invited_by.user.name
    @url = invitation_url(token)
    mail(to: invitation.email, subject: "Convite para a equipe #{@organization.name} no Servora")
  end
end
