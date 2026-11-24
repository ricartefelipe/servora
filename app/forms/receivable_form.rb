# frozen_string_literal: true

# Issuing a receivable for a work order.
class ReceivableForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :work_order_id, :string
  attribute :amount, :string
  attribute :due_on, :string
  attribute :description, :string

  validates :work_order_id, :amount, :due_on, presence: true

  def self.model_name = ActiveModel::Name.new(self, nil, "Receivable")
  def self.fields = %i[work_order_id amount due_on description]
end
