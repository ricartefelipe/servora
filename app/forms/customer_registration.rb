# frozen_string_literal: true

# New customer with its first service location and, optionally, the first
# contact — one screen, one transaction.
class CustomerRegistration
  include ActiveModel::Model
  include ActiveModel::Attributes

  CUSTOMER_FIELDS = %i[kind name trade_name document email phone notes].freeze
  LOCATION_FIELDS = %i[location_name street number complement district city state postal_code access_instructions].freeze
  CONTACT_FIELDS = %i[contact_name contact_email contact_phone contact_position contact_can_approve].freeze

  CUSTOMER_FIELDS.each { |field| attribute field, :string }
  LOCATION_FIELDS.each { |field| attribute field, :string }
  CONTACT_FIELDS.each { |field| attribute field, field == :contact_can_approve ? :boolean : :string }

  attr_reader :customer

  def self.model_name = ActiveModel::Name.new(self, nil, "Customer")

  def initialize(...)
    super
    self.kind ||= "company"
    self.location_name ||= "Principal"
  end

  def save(organization:) # rubocop:disable Naming/PredicateMethod -- ActiveModel save convention
    build(organization)
    return false unless valid_models?

    ActiveRecord::Base.transaction(requires_new: true) do
      @customer.save!
      @location.save!
      @contact&.save!
      AuditEvent.record!(action: "customer.created", auditable: @customer,
        changes: { name: @customer.name, kind: @customer.kind })
    end
    true
  end

  private

  def build(organization)
    @customer = organization.customers.new(attributes.symbolize_keys.slice(*CUSTOMER_FIELDS))
    @location = @customer.service_locations.new(location_attributes.merge(organization:))
    @contact = @customer.contacts.new(contact_attributes.merge(organization:)) if contact_name.present?
  end

  def location_attributes
    { name: location_name, street:, number:, complement:, district:, city:, state:, postal_code:, access_instructions: }
  end

  def contact_attributes
    { name: contact_name, email: contact_email, phone: contact_phone, position: contact_position,
      can_approve: contact_can_approve || false }
  end

  def valid_models?
    [[@customer, nil], [@location, "location"], [@contact, "contact"]].each do |model, prefix|
      next if model.nil? || model.valid?

      model.errors.each { |error| errors.add(field_name(prefix, error.attribute), error.message) }
    end
    errors.empty?
  end

  def field_name(prefix, attribute)
    return attribute unless prefix
    return :location_name if prefix == "location" && attribute == :name
    return attribute if prefix == "location"

    :"contact_#{attribute}"
  end
end
