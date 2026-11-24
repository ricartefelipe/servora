# frozen_string_literal: true

# Municipal service data for NFS-e issuance (the municipal registration and
# certificate are configured in the payment provider account).
class FiscalSettingsController < TenantController
  requires_module :finance

  before_action :load_setting

  def edit; end

  def update
    @setting.assign_attributes(params.expect(fiscal_setting: %i[municipal_service_code municipal_service_name iss_rate retain_iss
                                                                auto_issue_on_payment default_description]))
    if @setting.save
      AuditEvent.record!(action: "fiscal_setting.updated", auditable: @setting,
        changes: @setting.saved_changes.except("updated_at"))
      redirect_to edit_fiscal_settings_path, notice: "Dados fiscais salvos.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_setting
    authorize :integration, :manage?
    @setting = FiscalSetting.for(current_organization.id) || FiscalSetting.new(organization_id: current_organization.id,
      iss_rate: 0)
  end
end
