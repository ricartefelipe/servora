# frozen_string_literal: true

module Receivables
  # User-facing rule violations of the receivable use cases.
  module Errors
    class Invalid < Servora::RuleViolation; end

    module_function

    def translate(error) = Invalid.new(error.message)

    def lock_outstanding!(receivable)
      receivable.lock!("FOR NO KEY UPDATE")
      raise Invalid, "A conta #{receivable.number} está cancelada." if receivable.canceled?
    end

    # Writes a new position (amounts, status and settlement instant).
    def apply!(receivable, position)
      receivable.update!(
        amount: position.amount, discount_amount: position.discount, paid_amount: position.paid,
        refunded_amount: position.refunded, status: position.status,
        settled_at: position.settled? ? (receivable.settled_at || Time.current) : nil
      )
    end
  end
end
