# frozen_string_literal: true

# Public invitation page. Viewing never changes state; accepting is a POST by
# the signed-in user whose e-mail matches the invitation.
class InvitationAcceptancesController < ApplicationController
  layout "account"

  before_action :authenticate_user!, only: :create

  rate_limit to: 20, within: 10.minutes, name: "invitation",
    with: -> { redirect_to root_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

  def show
    @token = params[:token].to_s
    organization_id = Invitations::Accept.find_organization_id(@token)
    @invitation = organization_id && Servora::Tenancy.with_organization(organization_id) do
      Invitation.includes(:organization, invited_by: :user).find_by(token_digest: Invitation.digest(@token))
    end
    return render(:invalid, status: :not_found) unless @invitation

    store_location_for(:user, invitation_path(@token)) unless user_signed_in?
  end

  def create
    membership = Invitations::Accept.new(token: params[:token].to_s, user: current_user).call
    session[TenantController::ORGANIZATION_SESSION_KEY] = membership.organization_id
    redirect_to landing_path_for(membership), notice: "Bem-vindo à equipe!"
  rescue Servora::RuleViolation => e
    redirect_to invitation_path(params[:token].to_s), alert: e.message
  end
end
