# frozen_string_literal: true

# Charge registered at a payment provider. external_reference is ours and
# stable: it is sent with the charge and used to query the provider whenever
# a response was lost, so a retry never creates a second charge.
class PaymentCharge < TenantRecord
  STATUSES = { "pending" => "Aguardando envio", "submitted" => "Aguardando pagamento", "unknown" => "Em verificação",
               "confirmed" => "Paga", "failed" => "Recusada", "canceled" => "Cancelada" }.freeze
  ACTIVE_STATUSES = %w[pending submitted unknown].freeze
  BILLING_TYPES = { "pix" => "Pix", "boleto" => "Boleto" }.freeze
  PROVIDERS = { "simulator" => "Simulador", "asaas" => "Asaas (sandbox)" }.freeze

  belongs_to :receivable, inverse_of: :charges

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def status_label = STATUSES.fetch(status)
  def billing_type_label = BILLING_TYPES.fetch(billing_type)
  def provider_label = PROVIDERS.fetch(provider)
  def active? = ACTIVE_STATUSES.include?(status)
  def simulated? = provider == "simulator"
end
