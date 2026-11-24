# frozen_string_literal: true

# Append-only history of a receivable (UPDATE/DELETE revoked for the
# application role).
class FinancialEvent < TenantRecord
  LABELS = {
    "issued" => "Conta emitida", "payment" => "Pagamento registrado", "discount" => "Desconto concedido",
    "refund" => "Estorno", "canceled" => "Conta cancelada", "charge_requested" => "Cobrança solicitada",
    "charge_submitted" => "Cobrança registrada no provedor", "charge_confirmed" => "Cobrança paga",
    "charge_failed" => "Cobrança recusada", "charge_unknown" => "Resposta do provedor indefinida",
    "charge_canceled" => "Cobrança cancelada"
  }.freeze

  belongs_to :receivable, inverse_of: :events
  belongs_to :payment, optional: true

  def readonly? = persisted?
  def label = LABELS.fetch(kind)

  def self.record!(receivable:, kind:, amount: nil, payment: nil, actor: nil, details: {})
    create!(organization_id: receivable.organization_id, receivable:, kind:, amount:, payment:, details:,
      actor_membership_id: actor&.id, actor_label: actor&.user&.name || Current.actor_label, occurred_at: Time.current)
  end
end
