# frozen_string_literal: true

# Append-only inventory ledger entry, with the balance after the movement.
class StockMovement < TenantRecord
  KIND_LABELS = {
    "entry" => "Entrada", "reservation" => "Reserva", "reservation_release" => "Liberação de reserva",
    "consumption" => "Consumo", "return" => "Devolução", "transfer_out" => "Transferência (saída)",
    "transfer_in" => "Transferência (entrada)", "adjustment_in" => "Ajuste (entrada)", "adjustment_out" => "Ajuste (saída)"
  }.freeze

  belongs_to :warehouse
  belongs_to :catalog_item
  belongs_to :work_order, optional: true
  belongs_to :actor, class_name: "Membership", foreign_key: :actor_membership_id, optional: true, inverse_of: false

  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }

  def readonly? = persisted?
  def kind_label = KIND_LABELS.fetch(kind)
  def inbound? = %w[entry return transfer_in adjustment_in].include?(kind)
  def outbound? = %w[consumption transfer_out adjustment_out].include?(kind)
end
