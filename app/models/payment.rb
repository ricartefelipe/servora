# frozen_string_literal: true

# Money received for a receivable. Card data is never stored: card payments
# only exist as gateway charges confirmed by the provider.
class Payment < TenantRecord
  METHODS = { "pix" => "Pix", "boleto" => "Boleto", "transfer" => "Transferência", "cash" => "Dinheiro",
              "card_gateway" => "Cartão (via gateway)", "other" => "Outro" }.freeze
  MANUAL_METHODS = METHODS.except("card_gateway").freeze

  belongs_to :receivable, inverse_of: :payments
  belongs_to :charge, class_name: "PaymentCharge", foreign_key: :payment_charge_id, optional: true, inverse_of: false
  belongs_to :recorded_by, class_name: "Membership", foreign_key: :recorded_by_membership_id, optional: true,
    inverse_of: false

  def method_label = METHODS.fetch(payment_method)
  def refundable = amount - refunded_amount
end
