# frozen_string_literal: true

class DiscountForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :amount, :string
  attribute :reason, :string

  validates :amount, presence: true
  validates :reason, presence: true, length: { maximum: 500 }

  def self.model_name = ActiveModel::Name.new(self, nil, "Discount")
  def self.fields = %i[amount reason]
end
