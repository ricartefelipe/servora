# frozen_string_literal: true

class SettingsController < TenantController
  def edit
    @organization = current_organization
    authorize @organization, :update?
  end

  def update
    @organization = current_organization
    authorize @organization, :update?
    if @organization.update(settings_params)
      AuditEvent.record!(action: "organization.updated", auditable: @organization,
        changes: @organization.saved_changes.except("updated_at"))
      redirect_to edit_settings_path, notice: "Configurações salvas."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def complete_onboarding
    @organization = current_organization
    authorize @organization, :update?
    @organization.update!(onboarding_completed_at: Time.current) unless @organization.onboarding_completed?
    redirect_to dashboard_path, notice: "Primeiros passos concluídos."
  end

  private

  def settings_params
    params.expect(organization: %i[name legal_name document segment time_zone travel_buffer_minutes mfa_required_for_privileged])
  end
end
