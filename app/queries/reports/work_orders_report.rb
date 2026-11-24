# frozen_string_literal: true

module Reports
  # Work orders opened in the period: volume by status, origin and priority,
  # completions and average lead time (request → completion).
  class WorkOrdersReport < Base
    LEAD_HOURS = "avg(extract(epoch from work_orders.completed_at - work_orders.requested_at)) / 3600"
    CUSTOMER_NAME = "coalesce(nullif(customers.trade_name, ''), customers.name)"

    def title = "Ordens de serviço"

    def summary
      completed = WorkOrder.where(completed_at: range)
      { "Abertas no período" => scope.count, "Concluídas no período" => completed.count,
        "Canceladas no período" => WorkOrder.where(canceled_at: range).count,
        "Tempo médio até a conclusão (h)" => lead_hours(completed),
        by_status: scope.group(:status).count.transform_keys { |status| WorkOrders::LABELS.fetch(status, status) },
        by_origin: scope.group(:origin).count.transform_keys { |origin| WorkOrder::ORIGINS.fetch(origin, origin) } }
    end

    def headers = ["Número", "Título", "Cliente", "Situação", "Prioridade", "Origem", "Solicitada em", "Concluída em"]

    def rows(limit:)
      scope.joins(:customer).order(:requested_at).limit(limit)
        .pluck(:number, :title, Arel.sql(CUSTOMER_NAME), :status, :priority, :origin, :requested_at, :completed_at)
        .map { |row| present(row) }
    end

    private

    def scope = WorkOrder.where(requested_at: range)

    def lead_hours(completed)
      value = completed.pick(Arel.sql(LEAD_HOURS))
      value && BigDecimal(value.to_s).round(1)
    end

    def present(row)
      number, title, customer, status, priority, origin, requested, completed = row
      [number, title, customer, WorkOrders::LABELS.fetch(status, status), WorkOrder::PRIORITIES.fetch(priority, priority),
       WorkOrder::ORIGINS.fetch(origin, origin), local(requested), local(completed)]
    end
  end
end
