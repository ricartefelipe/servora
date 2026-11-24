# frozen_string_literal: true

# Manual payment registration (cash, transfer, Pix received outside a gateway charge).
class PaymentForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :amount, :string
  attribute :payment_method, :string, default: "pix"
  attribute :paid_on, :string
  attribute :notes, :string
  attribute :operation_key, :string

  validates :amount, :paid_on, presence: true
  validates :payment_method, inclusion: { in: Payment::MANUAL_METHODS.keys }
  validates :operation_key, format: { with: Servora::Tenancy::UUID_FORMAT }

  def self.model_name = ActiveModel::Name.new(self, nil, "Payment")
  def self.fields = %i[amount payment_method paid_on notes operation_key]

  def initialize(...)
    super
    self.operation_key ||= SecureRandom.uuid_v7
    self.paid_on ||= Time.zone.today.iso8601
  end

  # Payments registered for a past day are stamped at noon of that day.
  def paid_at
    date = Date.iso8601(paid_on.to_s)
    date == Time.zone.today ? Time.current : date.in_time_zone.change(hour: 12)
  rescue Date::Error
    nil
  end
end
