# frozen_string_literal: true

# Base class for every page inside an organization.
#
# The organization comes from the session but is never trusted on its own:
# each request re-reads the membership of the signed-in user (inside the RLS
# context) and denies access when it is missing or deactivated. The whole
# action, including view rendering, runs inside the tenant transaction so that
# lazily evaluated relations stay within the same context.
class TenantController < ApplicationController
  ORGANIZATION_SESSION_KEY = :organization_id

  before_action :authenticate_user!
  around_action :within_organization
  before_action :enforce_mfa_enrollment
  # Every action must call authorize; index actions must also use a policy scope.
  after_action :verify_authorized
  after_action :verify_policy_scoped, if: -> { action_name == "index" }

  layout "app"

  helper_method :current_membership, :current_organization, :can?

  private

  attr_reader :current_membership

  def current_organization
    current_membership&.organization
  end

  def can?(permission)
    current_membership&.can?(permission) || false
  end

  def pundit_user
    PolicyContext.new(user: current_user, membership: current_membership)
  end

  def within_organization(&)
    organization_id = session[ORGANIZATION_SESSION_KEY]
    return redirect_to(organizations_path) if organization_id.blank?

    Servora::Tenancy.with_context(organization_id:, user_id: current_user.id) do
      @current_membership = Membership.active.includes(:organization)
        .find_by(organization_id:, user_id: current_user.id)
      if @current_membership&.organization&.active?
        Current.set(membership: @current_membership, organization: @current_membership.organization) do
          Time.use_zone(@current_membership.organization.zone, &)
        end
      else
        leave_organization
      end
    end
  end

  def leave_organization
    session.delete(ORGANIZATION_SESSION_KEY)
    redirect_to organizations_path, alert: "Seu acesso a esta organização não está disponível."
  end

  def enforce_mfa_enrollment
    policy = Authentication::MfaRequirement.new(membership: current_membership, user: current_user)
    return unless policy.blocking?

    redirect_to new_account_two_factor_path,
      alert: "Ative a verificação em duas etapas para continuar acessando #{current_organization.name}."
  end

  def error_layout
    current_membership ? "app" : "application"
  end
end
