# frozen_string_literal: true

# Billing and margin figures of one work order, computed in SQL aggregates.
#
# * billable: authorized items (price agreed with the customer);
# * predicted: authorized items against their estimated unit costs;
# * realized: billed revenue (active receivables net of discounts) against
#   material at historical cost, labor at the hourly cost in force and
#   expenses.
class WorkOrderFinancialsQuery
  def initialize(work_order)
    @work_order = work_order
  end

  def billable_total = money(WorkOrderItem.where(work_order_id: id).authorized.sum(:line_total))
  def issued_total = money(Receivable.active.where(work_order_id: id).sum(:amount))
  def remaining_to_bill = [billable_total - issued_total, BigDecimal("0")].max

  def received_total
    money(Receivable.where(work_order_id: id).sum("receivables.paid_amount - receivables.refunded_amount"))
  end

  def predicted
    lines = WorkOrderItem.where(work_order_id: id).authorized.map(&:pricing_line)
    Pricing::Totals.from(lines)
  end

  def realized
    Finance::Margin.build(
      revenue: Receivable.active.where(work_order_id: id).sum("receivables.amount - receivables.discount_amount"),
      material_cost: MaterialConsumption.where(work_order_id: id)
        .sum("round((material_consumptions.quantity - material_consumptions.returned_quantity) " \
             "* material_consumptions.unit_cost, 2)"),
      labor_cost: TimeEntry.where(work_order_id: id).sum(:labor_cost),
      expenses: Expense.where(work_order_id: id).sum(:amount)
    )
  end

  private

  def id = @work_order.id
  def money(value) = Pricing::Amount.money(value)
end
