# frozen_string_literal: true

module Customers
  class Restore
    def initialize(customer:)
      @customer = customer
    end

    def call
      @customer.update!(archived_at: nil)
      AuditEvent.record!(action: "customer.restored", auditable: @customer)
      @customer
    end
  end
end
