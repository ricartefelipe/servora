# frozen_string_literal: true

module Portal
  class HomeController < BaseController
    def show
      @pending_quotes = customer_scope(Quote).where(status: "sent").includes(:current_version).order(created_at: :desc).limit(10)
      @open_orders = customer_scope(WorkOrder).open_work.count
      @next_visit = Visit.joins(:work_order).merge(customer_scope(WorkOrder)).where(status: "scheduled")
        .where(scheduled_start: Time.current..).order(:scheduled_start).first
      @open_balance = customer_scope(Receivable).outstanding
        .sum(Arel.sql(ReceivablesSummaryQuery::BALANCE_SQL))
    end
  end
end
