# frozen_string_literal: true

module Dashboards
  # The day at a glance for the dashboard: the cover figures, the list of items
  # that need attention (ordered by severity) and the next visits. Every figure
  # honours the member's permissions and the subscription modules; visits and
  # stock come already narrowed by the caller's policy scopes. Runs inside the
  # request's tenant context and time zone.
  class Today
    Cover = Data.define(:visits_total, :visits_done, :in_field, :open_orders, :upcoming) do
      def progress = visits_total.zero? ? 0 : (visits_done * 100 / visits_total)
    end

    # severity: :high (danger) or :medium (warning). route/params build the link
    # to the pre-filtered list where the item is resolved; actionable tells
    # whether the member may resolve it there ("Resolver") or only look ("Ver").
    Attention = Data.define(:key, :count, :label, :severity, :route, :params, :actionable)

    # One slice of the open work orders, in lifecycle order.
    StatusSlice = Data.define(:status, :label, :count)

    # Money received on one calendar day of the organization (net of refunds).
    DailyReceipt = Data.define(:date, :amount, :today)

    UPCOMING_LIMIT = 6
    RECEIPT_DAYS = 7
    NET_RECEIVED_SQL = "payments.amount - payments.refunded_amount"

    def initialize(membership:, visits:, stock_balances:, today: Time.zone.today, now: Time.current)
      @membership = membership
      @organization = membership.organization
      @visits = visits
      @stock_balances = stock_balances
      @today = today
      @now = now
    end

    def cover
      todays = @visits.where(scheduled_start: @today.all_day).where.not(status: %w[canceled no_show])
      Cover.new(
        visits_total: todays.count,
        visits_done: todays.where(status: "completed").count,
        in_field: @visits.where(status: Visits::IN_FIELD).count,
        open_orders: (WorkOrder.open_work.count if can?(:work_orders_view_all)),
        upcoming: upcoming_scope.count
      )
    end

    # Receivable headline figures for members who follow the money rather than
    # the schedule (nil when finance is not visible or not in the plan).
    def finance
      return nil unless can?(:finance_view) && module?(:finance)

      ReceivablesSummaryQuery.new(@organization.receivables, today: @today).call
    end

    def attention
      (high_attention + medium_attention).select { |item| item.count.nonzero? }
    end

    # Number of areas checked, so an empty list can say "tudo em dia em N áreas".
    def areas_checked = (high_attention + medium_attention).map(&:key).uniq.size

    def upcoming_visits
      upcoming_scope.includes(work_order: %i[customer service_location]).limit(UPCOMING_LIMIT).to_a
    end

    # Open receivables by due date (overdue ones come first), for members who
    # follow the money (nil when finance is not visible or not in the plan).
    def upcoming_receivables
      return nil unless can?(:finance_view) && module?(:finance)

      @upcoming_receivables ||= @organization.receivables.outstanding.includes(:customer)
        .order(:due_on, :number).limit(UPCOMING_LIMIT).to_a
    end

    # Open work orders grouped by status, lifecycle order, empty statuses left
    # out (nil without permission to see every work order).
    def open_orders_by_status
      return nil unless can?(:work_orders_view_all)

      @open_orders_by_status ||= begin
        counts = WorkOrder.open_work.group(:status).count
        WorkOrders::LABELS.filter_map do |status, label|
          StatusSlice.new(status:, label:, count: counts[status]) if counts[status].to_i.positive?
        end
      end
    end

    # Net money received on each of the last RECEIPT_DAYS days, oldest first and
    # ending today. Days follow the organization's time zone; a refund lowers the
    # day the payment was received (nil when finance is not visible or not in the
    # plan).
    def daily_receipts
      return nil unless can?(:finance_view) && module?(:finance)

      @daily_receipts ||= begin
        days = (@today - (RECEIPT_DAYS - 1))..@today
        sums = received_per_day(days, @organization.zone)
        days.map { |date| DailyReceipt.new(date:, amount: Pricing::Amount.money(sums.fetch(date, 0)), today: date == @today) }
      end
    end

    private

    def high_attention
      @high_attention ||= [
        (sla_item(:breached, "OS com prazo estourado", :high) if can?(:work_orders_view_all)),
        (equipment_item("inoperative", "Equipamentos parados", :high) if can?(:equipment_view)),
        (overdue_receivables if can?(:finance_view) && module?(:finance))
      ].compact
    end

    def medium_attention
      @medium_attention ||= [
        (sla_item(:at_risk, "OS com prazo em risco", :medium) if can?(:work_orders_view_all)),
        (equipment_item("attention", "Equipamentos em atenção", :medium) if can?(:equipment_view)),
        (stock_below_minimum if can?(:inventory_view) && module?(:inventory))
      ].compact
    end

    # Work orders (not deadlines) with a running deadline past or at risk; an
    # order with both appears in each item, like in the filtered lists.
    def sla_item(kind, label, severity)
      orders = kind == :breached ? WorkOrder.deadline_overdue(@now) : WorkOrder.deadline_at_risk(@now)
      Attention.new(key: :"sla_#{kind}", count: orders.count, label:, severity:, route: :work_orders_path,
        params: { prazo: kind == :breached ? "estourado" : "em_risco" }, actionable: can?(:work_orders_manage))
    end

    def equipment_item(status, label, severity)
      count = @organization.equipment.active.where(operational_status: status).count
      Attention.new(key: :"equipment_#{status}", count:, label:, severity:, route: :equipment_index_path,
        params: { estado: status }, actionable: can?(:equipment_manage))
    end

    def overdue_receivables
      Attention.new(key: :receivables_overdue, count: @organization.receivables.overdue(@today).count,
        label: "Contas vencidas", severity: :high, route: :receivables_path, params: { situacao: "overdue" },
        actionable: can?(:finance_manage))
    end

    def stock_below_minimum
      count = @stock_balances.where(StockBalance::BELOW_MINIMUM_SQL).count
      Attention.new(key: :stock_below_minimum, count:, label: "Itens abaixo do estoque mínimo", severity: :medium,
        route: :stock_balances_path, params: { abaixo: "1" }, actionable: can?(:inventory_manage))
    end

    # Sum of net payments keyed by the local date they were received on.
    def received_per_day(days, zone)
      local_date = "(payments.paid_at AT TIME ZONE #{Payment.connection.quote(zone.tzinfo.name)})::date"
      Payment.where(organization_id: @organization.id)
        .where(paid_at: days.first.in_time_zone(zone)...(days.last + 1).in_time_zone(zone))
        .group(Arel.sql(local_date)).sum(Arel.sql(NET_RECEIVED_SQL))
    end

    def upcoming_scope = @visits.upcoming.where(scheduled_end: @now..)

    def can?(permission) = @membership.can?(permission)
    def module?(code) = @organization.module_enabled?(code)
  end
end
