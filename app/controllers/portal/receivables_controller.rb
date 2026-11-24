# frozen_string_literal: true

module Portal
  # Charges of the customer: what is open, paid and the payment link of an
  # active provider charge. This is not a tax invoice.
  class ReceivablesController < BaseController
    def index
      @receivables = customer_scope(Receivable).active.includes(:work_order).order(due_on: :desc).limit(100)
      @charges = PaymentCharge.where(receivable_id: @receivables.map(&:id), status: %w[submitted unknown])
        .where.not(payment_url: nil).index_by(&:receivable_id)
    end
  end
end
