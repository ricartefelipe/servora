# frozen_string_literal: true

module Invoices
  module Handlers
    # receivable.settled → request the NFS-e when the organization issues
    # invoices automatically on payment (and none is valid yet).
    class AutoIssue
      def call(event, _context)
        settings = FiscalSetting.for(event.organization_id)
        return unless settings&.auto_issue_on_payment

        receivable = Receivable.find(event.aggregate_id)
        return if receivable.canceled? || ServiceInvoice.valid.exists?(receivable_id: receivable.id)

        Invoices::Request.new(receivable:, actor: nil).call
      end
    end
  end
end
