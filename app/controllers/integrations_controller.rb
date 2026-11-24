# frozen_string_literal: true

# Integrations overview: API credentials, outbound webhooks and the payment
# provider notification token. Secrets are rendered once, right after
# creation, and never stored in plain text or flash messages.
class IntegrationsController < TenantController
  requires_module :api

  before_action { authorize :integration, :show? }

  def show
    load_page
  end

  # Creates an API credential and shows its token once.
  def create_credential
    authorize :integration, :manage?
    attributes = params.expect(api_credential: [:name, :expires_on, { scopes: [] }])
    credential, token = Integrations::CreateCredential.new(organization: current_organization, actor: current_membership,
      name: attributes[:name], scopes: attributes[:scopes], expires_on: attributes[:expires_on]).call
    reveal("Token da credencial #{credential.name}", token)
  rescue ActiveRecord::RecordInvalid, Servora::RuleViolation => e
    invalid(e)
  end

  def revoke_credential
    authorize :integration, :manage?
    credential = tenant_relation(ApiCredential).find(params.expect(:id))
    credential.update!(revoked_at: Time.current) unless credential.revoked_at
    AuditEvent.record!(action: "api_credential.revoked", auditable: credential)
    redirect_to integrations_path, notice: "Credencial revogada. Requisições com ela passam a ser recusadas.", status: :see_other
  end

  # Creates a webhook endpoint and shows its signing secret once.
  def create_endpoint
    authorize :integration, :manage?
    attributes = params.expect(webhook_endpoint: [:url, :description, { events: [] }])
    _endpoint, secret = Integrations::CreateEndpoint.new(organization: current_organization, url: attributes[:url],
      description: attributes[:description], events: attributes[:events]).call
    reveal("Segredo de assinatura do webhook", secret)
  rescue ActiveRecord::RecordInvalid => e
    invalid(e)
  end

  def toggle_endpoint
    authorize :integration, :manage?
    endpoint = tenant_relation(WebhookEndpoint).find(params.expect(:id))
    endpoint.update!(active: !endpoint.active)
    AuditEvent.record!(action: "webhook_endpoint.#{endpoint.active ? "enabled" : "disabled"}", auditable: endpoint)
    redirect_to integrations_path, notice: endpoint.active ? "Webhook ativado." : "Webhook desativado.", status: :see_other
  end

  def redeliver
    authorize :integration, :manage?
    delivery = tenant_relation(WebhookDelivery).find(params.expect(:id))
    delivery.update!(status: "pending", attempts: 0, last_error: nil) unless delivery.status == "delivered"
    Webhooks::DeliverJob.perform_later(current_organization.id, delivery.id) if delivery.status == "pending"
    AuditEvent.record!(action: "webhook_delivery.redelivered", auditable: delivery)
    redirect_to integrations_path, notice: "Reenvio agendado.", status: :see_other
  end

  # Rotates the token Asaas must send with payment notifications.
  def rotate_payment_token
    authorize :integration, :manage?
    token = SecureRandom.urlsafe_base64(32)
    integration = PaymentIntegration.for(current_organization.id)
    integration.update!(webhook_token_digest: PaymentIntegration.webhook_digest(token))
    AuditEvent.record!(action: "payment_integration.webhook_token_rotated", auditable: integration)
    reveal("Token de notificações do Asaas (configure em asaas-access-token)", token, url: asaas_webhook_url)
  end

  private

  def reveal(title, secret, url: nil)
    @secret = { title:, value: secret, url: }
    load_page
    render :show, status: :created
  end

  def invalid(error)
    load_page
    flash.now[:alert] = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message
    render :show, status: :unprocessable_content
  end

  def load_page
    @credentials = tenant_relation(ApiCredential).order(created_at: :desc)
    @endpoints = tenant_relation(WebhookEndpoint).order(:created_at)
    @deliveries = tenant_relation(WebhookDelivery).includes(:webhook_endpoint).recent_first.limit(30)
    @payment_integration = PaymentIntegration.for(current_organization.id)
  end
end
