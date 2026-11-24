# frozen_string_literal: true

# Monthly invoice of the platform subscription.
class SubscriptionInvoice < TenantRecord
  STATUSES = { "open" => "Em aberto", "paid" => "Paga", "void" => "Anulada" }.freeze
  GRACE_DAYS = 7

  belongs_to :subscription

  scope :recent_first, -> { order(period_start: :desc) }
  scope :open_invoices, -> { where(status: "open") }

  def status_label = overdue? ? "Vencida" : STATUSES.fetch(status)
  def overdue?(today = Time.zone.today) = status == "open" && due_on < today
  def delinquent?(today = Time.zone.today) = status == "open" && due_on + GRACE_DAYS < today

  # Read-only view in the shape the payment gateways expect from a charge.
  def as_gateway_charge
    Payments::Gateways::PlatformCharge.new(external_reference:, external_id:, amount:, due_on: [due_on, Time.zone.today].max,
      billing_type: "pix", attempts:, status: charge_status)
  end
end
