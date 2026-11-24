# frozen_string_literal: true

module Portal
  # Portal start page: a summary of what concerns the contact's customer
  # (upcoming visits, quotes awaiting a decision, open charges and work in
  # progress) followed by the quotes awaiting a decision. Every figure goes
  # through customer_scope inside the portal session's tenant, so it never
  # includes another customer or organization.
  class HomeController < BaseController
    def show
      @can_approve = current_contact.can_approve?
      @pending_quotes = awaiting_decision.includes(:current_version).order(created_at: :desc).limit(10)
      @pending_quotes_count = awaiting_decision.count
      @open_orders = customer_scope(WorkOrder).open_work.count
      load_visits
      load_receivables
    end

    private

    # Same rule as the portal decision: the quote is sent and its current
    # version is the one awaiting a decision, still within its validity.
    # Only approver contacts can decide; the others see the same quotes as
    # awaiting their company's approvers.
    def awaiting_decision
      customer_scope(Quote).where(status: "sent").joins(:current_version)
        .where(quote_versions: { status: "sent", valid_until: Time.zone.today.. })
    end

    # Scheduled visits not yet ended, plus any visit on the way or under way
    # (even past its planned end).
    def load_visits
      visits = Visit.joins(:work_order).merge(customer_scope(WorkOrder))
        .merge(Visit.where(status: Visits::IN_FIELD).or(Visit.where(status: "scheduled", scheduled_end: Time.current..)))
      @upcoming_visits = visits.count
      @next_visit = visits.order(:scheduled_start).first
    end

    def load_receivables
      outstanding = customer_scope(Receivable).outstanding
      @open_receivables = outstanding.count
      @open_balance = outstanding.sum(Arel.sql(ReceivablesSummaryQuery::BALANCE_SQL))
      @overdue_receivables = customer_scope(Receivable).overdue(Time.zone.today).count
    end
  end
end
