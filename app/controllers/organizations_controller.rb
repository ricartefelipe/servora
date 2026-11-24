# frozen_string_literal: true

# Organization picker and onboarding of a new organization. Listing runs with
# only the user context set, so RLS exposes exactly the organizations in which
# the user holds an active membership.
class OrganizationsController < AuthenticatedController
  rate_limit to: 5, within: 1.hour, only: :create, name: "organization-create",
    with: -> { redirect_to organizations_path, alert: "Muitas tentativas. Tente novamente mais tarde." }

  def index
    @memberships = Servora::Tenancy.with_context(user_id: current_user.id) do
      current_user.active_memberships.to_a.select { |m| m.organization.active? }
    end
    return redirect_to(new_organization_path) if @memberships.empty?

    select_and_redirect(@memberships.first) if @memberships.one? && params[:escolher].blank?
  end

  def new
    @registration = OrganizationRegistration.new
  end

  def create
    @registration = OrganizationRegistration.new(registration_params)
    if @registration.save(user: current_user)
      session[TenantController::ORGANIZATION_SESSION_KEY] = @registration.organization.id
      redirect_to dashboard_path, notice: "Organização criada. Vamos configurar os primeiros passos."
    else
      render :new, status: :unprocessable_content
    end
  end

  def select
    membership = Servora::Tenancy.with_context(user_id: current_user.id) do
      current_user.memberships.active.includes(:organization).find_by(organization_id: params[:id])
    end
    raise ActiveRecord::RecordNotFound unless membership&.organization&.active?

    select_and_redirect(membership)
  end

  private

  def select_and_redirect(membership)
    reset_session_preserving_authentication
    session[TenantController::ORGANIZATION_SESSION_KEY] = membership.organization_id
    redirect_to dashboard_path
  end

  # Switching organizations rotates the session id (fixation protection) and
  # drops any data tied to the previous organization.
  def reset_session_preserving_authentication
    warden_data = session.to_hash.slice("warden.user.user.key", "warden.user.user.session")
    reset_session
    warden_data.each { |key, value| session[key] = value }
  end

  def registration_params
    params.expect(organization: %i[name legal_name document segment time_zone travel_buffer_minutes])
  end
end
