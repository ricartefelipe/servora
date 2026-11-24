# frozen_string_literal: true

module Quotes
  # Frozen document data of a version at the moment it is sent: everything the
  # customer sees (and approves) without depending on mutable records. Internal
  # costs are never included.
  class SnapshotBuilder
    def initialize(version)
      @version = version
      @quote = version.quote
    end

    def call
      {
        "quote" => { "number" => @quote.number, "title" => @quote.title, "version" => @version.version_number },
        "organization" => organization_data,
        "customer" => customer_data,
        "location" => location_data,
        "items" => @version.items.map { |item| item_data(item) },
        "totals" => { "subtotal" => money(@version.subtotal), "discount" => money(@version.discount_amount),
                      "total" => money(@version.total) },
        "terms" => { "valid_until" => @version.valid_until.iso8601, "payment_terms" => @version.payment_terms.to_s,
                     "notes" => @version.notes.to_s },
        "currency" => "BRL"
      }
    end

    private

    def organization_data
      organization = @quote.organization
      { "name" => organization.name, "legal_name" => organization.legal_name.to_s, "document" => organization.document.to_s }
    end

    def customer_data
      customer = @quote.customer
      { "name" => customer.name, "trade_name" => customer.trade_name.to_s, "document" => customer.document.to_s }
    end

    def location_data
      location = @quote.service_location
      { "name" => location.name, "address" => location.address_line, "city" => location.city_line }
    end

    def item_data(item)
      { "kind" => item.kind, "description" => item.description, "unit" => item.unit, "quantity" => item.quantity.to_s("F"),
        "unit_price" => money(item.unit_price), "discount" => money(item.discount_amount), "total" => money(item.line_total) }
    end

    def money(value) = Pricing::Amount.money(value).to_s("F")
  end
end
