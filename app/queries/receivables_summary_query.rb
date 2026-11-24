# frozen_string_literal: true

# Headline figures of the receivables screen.
class ReceivablesSummaryQuery
  Summary = Data.define(:outstanding, :overdue, :received_this_month)

  BALANCE_SQL = "receivables.amount - receivables.discount_amount - receivables.paid_amount + receivables.refunded_amount"

  def initialize(scope, today: Time.zone.today)
    @scope = scope
    @today = today
  end

  def call
    Summary.new(
      outstanding: money(@scope.outstanding.sum(Arel.sql(BALANCE_SQL))),
      overdue: money(@scope.overdue(@today).sum(Arel.sql(BALANCE_SQL))),
      received_this_month: money(Payment.where(receivable_id: @scope.select(:id))
        .where(paid_at: @today.beginning_of_month.in_time_zone..).sum("payments.amount - payments.refunded_amount"))
    )
  end

  private

  def money(value) = Pricing::Amount.money(value)
end
