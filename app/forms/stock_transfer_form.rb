# frozen_string_literal: true

# Transfer between warehouses (e.g. central storeroom → technician vehicle).
class StockTransferForm < StockOperationForm
  attribute :destination_id, :string

  validates :destination_id, presence: true

  def self.model_name = ActiveModel::Name.new(self, nil, "StockTransfer")
  def self.fields = super + %i[destination_id]

  private

  def perform(actor)
    Inventory::Transfer.new(from: warehouse, to: @warehouses.find(destination_id), item:, quantity:, actor:, reason:,
      idempotency_key: operation_key).call
  end
end
