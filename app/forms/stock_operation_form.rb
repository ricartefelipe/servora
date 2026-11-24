# frozen_string_literal: true

# Base for stock operations submitted from the inventory screens. Records are
# resolved only through relations already restricted by policy scopes, and
# every rule violation becomes a form error rendered back into the modal.
#
# operation_key is generated when the form is opened; submitting the same form
# twice (double click, browser retry) replays the first result instead of
# moving stock again.
class StockOperationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :warehouse_id, :string
  attribute :catalog_item_id, :string
  attribute :quantity, :string
  attribute :reason, :string
  attribute :operation_key, :string

  validates :warehouse_id, :catalog_item_id, :quantity, :operation_key, presence: true
  validates :operation_key, format: { with: Servora::Tenancy::UUID_FORMAT }, allow_blank: true

  attr_reader :result

  def self.fields = %i[warehouse_id catalog_item_id quantity reason operation_key]

  def initialize(...)
    super
    self.operation_key ||= SecureRandom.uuid_v7
  end

  def submit(warehouses:, items:, actor:)
    return false unless valid?

    @warehouses = warehouses
    @items = items
    @result = perform(actor)
    true
  rescue ActiveRecord::RecordNotFound
    errors.add(:base, "Depósito ou item indisponível para esta operação.")
    false
  rescue Pricing::Amount::InvalidValue
    errors.add(:quantity, "deve ser um número válido")
    false
  rescue Servora::RuleViolation => e
    errors.add(:base, e.message)
    false
  end

  private

  def perform(_actor) = raise(NotImplementedError)

  def warehouse = @warehouses.find(warehouse_id)
  def item = @items.find(catalog_item_id)
end
