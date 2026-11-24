# frozen_string_literal: true

# Payment provider settings. The stored API key is never sent back to the
# browser; leaving the field blank keeps it.
class PaymentIntegrationsController < TenantController
  requires_module :finance

  before_action :load_integration

  def edit; end

  def update
    attributes = params.expect(payment_integration: %i[provider default_billing_type api_key])
    attributes.delete(:api_key) if attributes[:api_key].blank?
    @integration.assign_attributes(attributes)
    if @integration.save
      AuditEvent.record!(action: "payment_integration.updated", auditable: @integration,
        changes: { provider: @integration.provider, api_key: (attributes.key?(:api_key) ? "[ALTERADA]" : nil) }.compact)
      redirect_to edit_payment_integration_path, notice: "Integração de pagamentos atualizada.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_integration
    @integration = PaymentIntegration.for(current_organization.id)
    authorize @integration, :update?
  end
end
