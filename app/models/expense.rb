# frozen_string_literal: true

# Direct cost of a work order other than material and labor.
class Expense < TenantRecord
  CATEGORIES = { "travel" => "Deslocamento", "toll" => "Pedágio", "parking" => "Estacionamento", "meals" => "Alimentação",
                 "outsourced" => "Serviço terceirizado", "materials" => "Material comprado avulso", "other" => "Outros" }.freeze

  belongs_to :work_order, inverse_of: :expenses
  belongs_to :recorded_by, class_name: "Membership", foreign_key: :recorded_by_membership_id, optional: true,
    inverse_of: false

  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :description, presence: true, length: { maximum: 200 }
  validates :amount, numericality: { greater_than: 0 }
  validates :incurred_on, presence: true

  def category_label = CATEGORIES.fetch(category)
end
