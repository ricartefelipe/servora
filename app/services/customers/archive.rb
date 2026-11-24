# frozen_string_literal: true

module Customers
  # Archiving hides a customer from new operations while preserving history.
  class Archive
    def initialize(customer:)
      @customer = customer
    end

    def call
      @customer.update!(archived_at: Time.current)
      AuditEvent.record!(action: "customer.archived", auditable: @customer)
      @customer
    end
  end
end
