# frozen_string_literal: true

# Service or material of a work order. Items copied from the approved quote
# are authorized; additional items start pending and are only billable once
# authorized (with the customer contact and channel recorded).
class WorkOrderItem < TenantRecord
  SOURCES = { "quote" => "Orçamento aprovado", "additional" => "Serviço adicional", "preventive" => "Plano preventivo",
              "manual" => "Lançamento interno" }.freeze
  AUTHORIZATION_LABELS = { "authorized" => "Autorizado", "pending" => "Aguardando autorização", "rejected" => "Recusado" }.freeze

  belongs_to :work_order, inverse_of: :items
  belongs_to :catalog_item, optional: true
  belongs_to :authorized_by_contact, class_name: "CustomerContact", optional: true
  belongs_to :authorized_by_membership, class_name: "Membership", optional: true

  validates :kind, inclusion: { in: QuoteItem::KINDS.keys }
  validates :source, inclusion: { in: SOURCES.keys }
  validates :authorization_status, inclusion: { in: AUTHORIZATION_LABELS.keys }
  validates :description, presence: true, length: { maximum: 240 }

  scope :authorized, -> { where(authorization_status: "authorized") }
  scope :pending_authorization, -> { where(authorization_status: "pending") }

  def pricing_line = Pricing::Line.build(quantity:, unit_price:, discount: discount_amount, unit_cost:)
  def authorization_label = AUTHORIZATION_LABELS.fetch(authorization_status)
  def pending? = authorization_status == "pending"
end
