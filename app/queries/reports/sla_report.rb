# frozen_string_literal: true

module Reports
  # Deadlines closed in the period (met or breached) by priority and metric,
  # and deadlines currently overdue.
  class SlaReport < Base
    MET_COUNT = "count(*) FILTER (WHERE sla_clocks.status = 'met')"
    # Rows go from the most to the least severe priority, then by metric in
    # the order a work order meets them.
    SEVERITY = %w[urgent high normal low].freeze

    def title = "Prazos (SLA)"

    def summary
      closed = SlaClock.where(stopped_at: range, status: %w[met breached])
      met = closed.where(status: "met").count
      total = closed.count
      { "Prazos encerrados" => total, "Cumpridos" => met, "Estourados" => total - met,
        "Percentual cumprido" => Percent.of(met, total),
        "Estourados em andamento" => SlaClock.running.where(due_at: ...Time.current).count }
    end

    def headers = ["Métrica", "Prioridade", "Encerrados", "Cumpridos", "Estourados", "Percentual cumprido"]

    def rows(limit:)
      SlaClock.joins(:work_order).where(stopped_at: range, status: %w[met breached])
        .group(:metric, "work_orders.priority")
        .pluck(:metric, "work_orders.priority", Arel.sql("count(*)"), Arel.sql(MET_COUNT))
        .sort_by { |metric, priority| [SEVERITY.index(priority) || SEVERITY.size, SlaClock::METRICS.keys.index(metric)] }
        .first(limit).map do |metric, priority, total, met|
          [SlaClock::METRICS.fetch(metric), WorkOrder::PRIORITIES.fetch(priority, priority), total, met, total - met,
           Percent.of(met, total)]
        end
    end
  end
end
