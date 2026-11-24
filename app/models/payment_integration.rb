# frozen_string_literal: true

# Payment provider of the organization. The API key is encrypted at rest
# (Active Record Encryption) and never rendered back to the browser.
class PaymentIntegration < TenantRecord
  encrypts :api_key

  validates :provider, inclusion: { in: PaymentCharge::PROVIDERS.keys }
  validates :default_billing_type, inclusion: { in: PaymentCharge::BILLING_TYPES.keys }
  validates :api_key, presence: { message: "é obrigatória para o Asaas" }, if: -> { provider == "asaas" }

  def self.for(organization_id) = find_by(organization_id:) || new(organization_id:, provider: "simulator")

  def provider_label = PaymentCharge::PROVIDERS.fetch(provider)
  def credential_configured? = api_key.present?
end
