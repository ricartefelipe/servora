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
    # to the pre-filtered list where the item is resolved.
    Attention = Data.define(:key, :count, :label, :severity, :route, :params)

    UPCOMING_LIMIT = 6

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
        in_field: @visits.where(status: "in_progress").count,
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

    def sla_item(kind, label, severity)
      running = SlaClock.running
      count = kind == :breached ? running.where(due_at: ..@now).count : running.where(due_at: @now..).where(warn_at: ..@now).count
      Attention.new(key: :"sla_#{kind}", count:, label:, severity:, route: :work_orders_path, params: {})
    end

    def equipment_item(status, label, severity)
      count = @organization.equipment.active.where(operational_status: status).count
      Attention.new(key: :"equipment_#{status}", count:, label:, severity:, route: :equipment_index_path,
        params: { estado: status })
    end

    def overdue_receivables
      Attention.new(key: :receivables_overdue, count: @organization.receivables.overdue(@today).count,
        label: "Contas vencidas", severity: :high, route: :receivables_path, params: { situacao: "overdue" })
    end

    def stock_below_minimum
      count = @stock_balances.where(StockBalance::BELOW_MINIMUM_SQL).count
      Attention.new(key: :stock_below_minimum, count:, label: "Itens abaixo do estoque mínimo", severity: :medium,
        route: :stock_balances_path, params: { abaixo: "1" })
    end

    def upcoming_scope = @visits.upcoming.where(scheduled_end: @now..)

    def can?(permission) = @membership.can?(permission)
    def module?(code) = @organization.module_enabled?(code)
  end
end
