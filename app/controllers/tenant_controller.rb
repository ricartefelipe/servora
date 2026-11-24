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
  before_action :enforce_subscription_access
  # Every action must call authorize; index actions must also use a policy scope.
  after_action :verify_authorized
  after_action :verify_policy_scoped, if: -> { action_name == "index" }

  layout "app"

  helper_method :current_membership, :current_organization, :can?, :module_enabled?, :current_subscription

  # Restricts a controller to organizations whose subscription includes the
  # module (inventory, preventive, finance, api).
  def self.requires_module(code)
    before_action { require_module!(code) }
  end

  private

  attr_reader :current_membership

  def current_organization
    current_membership&.organization
  end

  def can?(permission)
    current_membership&.can?(permission) || false
  end

  def current_subscription
    return @current_subscription if defined?(@current_subscription)

    @current_subscription = current_organization && Subscription.includes(:plan).find_by(organization_id: current_organization.id)
  end

  def module_enabled?(code) = current_subscription.nil? || current_subscription.module_enabled?(code)

  def require_module!(code)
    return if module_enabled?(code)

    redirect_to dashboard_path,
      alert: "Este recurso não faz parte do plano atual. Fale com o proprietário da conta para incluí-lo."
  end

  # After the trial (or with a pending/canceled subscription) the organization
  # keeps reading its data but cannot register changes, except on the
  # subscription page.
  def enforce_subscription_access
    return if request.get? || request.head? || !current_subscription&.read_only?
    return if controller_name == "subscriptions"

    redirect_back_or_to dashboard_path, status: :see_other,
      alert: "A avaliação terminou ou a assinatura está pendente: os dados seguem disponíveis para consulta. " \
             "Ative a assinatura para voltar a registrar."
  end

  # Explicitly tenant-scoped relation (RLS enforces the same rule). Used to load
  # single records: rows loaded through a has_many of the organization would
  # be flagged for strict loading as if they were part of an N+1 iteration.
  def tenant_relation(model)
    model.where(organization_id: current_organization.id)
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
