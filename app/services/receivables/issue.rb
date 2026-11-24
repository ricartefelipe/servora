# frozen_string_literal: true

module Receivables
  # Issues a receivable (or an installment) for a work order. The sum of active
  # receivables never exceeds what the customer authorized; the work order row
  # lock serializes concurrent issuing.
  class Issue
    def initialize(work_order:, amount:, due_on:, actor:, description: nil)
      @work_order = work_order
      @amount = amount
      @due_on = due_on
      @actor = actor
      @description = description.to_s.squish.presence
    end

    def call
      position = Position.issue(@amount)
      due_on = parse_date!
      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        ensure_billable!(position.amount)
        create(position, due_on)
      end
    rescue Receivables::Rejected => e
      raise Errors.translate(e)
    end

    private

    def parse_date!
      date = @due_on.is_a?(Date) ? @due_on : Date.iso8601(@due_on.to_s)
      raise Errors::Invalid, "O vencimento não pode ser anterior a hoje." if date < Time.zone.today

      date
    rescue Date::Error
      raise Errors::Invalid, "Informe um vencimento válido."
    end

    def ensure_billable!(amount)
      raise Errors::Invalid, "Ordem cancelada não pode ser faturada." if @work_order.canceled?

      remaining = WorkOrderFinancialsQuery.new(@work_order).remaining_to_bill
      return if amount <= remaining

      raise Errors::Invalid, "O valor supera o saldo a faturar da ordem (#{Pricing::Format.brl(remaining)})."
    end

    def create(position, due_on)
      receivable = Receivable.create!(
        organization_id: @work_order.organization_id, work_order: @work_order, customer_id: @work_order.customer_id,
        number: Numbering.next!(organization: @work_order.organization, scope: "receivable"),
        description: @description || "Ordem de serviço #{@work_order.number}", amount: position.amount, due_on:,
        status: position.status, created_by_membership_id: @actor&.id
      )
      FinancialEvent.record!(receivable:, kind: "issued", amount: position.amount, actor: @actor,
        details: { due_on: due_on.iso8601 })
      AuditEvent.record!(action: "receivable.issued", auditable: receivable,
        changes: { number: receivable.number, amount: position.amount, due_on: })
      receivable
    end
  end
end
