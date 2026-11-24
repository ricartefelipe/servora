# frozen_string_literal: true

module Reports
  # Per technician: work orders completed (assigned), visits finished, hours
  # logged and, with the cost permission, the labor cost recorded.
  class ProductivityReport < Base
    def title = "Produtividade por técnico"

    def summary
      data = technicians
      { "Técnicos com atividade" => data.count { |row| row[:hours].positive? || row[:visits].positive? },
        "Visitas concluídas" => data.sum { |row| row[:visits] },
        "Horas apontadas" => data.sum(BigDecimal("0")) { |row| row[:hours] } }
    end

    def headers
      base = ["Técnico", "Ordens concluídas", "Visitas concluídas", "Horas apontadas"]
      @show_costs ? base + ["Custo de mão de obra"] : base
    end

    def rows(limit:)
      technicians.first(limit).map do |row|
        base = [row[:name], row[:completed], row[:visits], row[:hours]]
        @show_costs ? base + [row[:labor_cost]] : base
      end
    end

    private

    def technicians
      @technicians ||= begin
        completed = completed_orders
        visits = finished_visits
        entries = logged_time
        Membership.where(role: "technician").joins(:user).order("users.name").pluck(:id, "users.name").map do |id, name|
          minutes, cost = entries.fetch(id, [0, 0])
          { name:, completed: completed.fetch(id, 0), visits: visits.fetch(id, 0), hours: hours(minutes),
            labor_cost: money(cost) }
        end
      end
    end

    def completed_orders
      WorkOrderAssignment.joins(:work_order).where(work_orders: { completed_at: range }).group(:membership_id).count
    end

    def finished_visits
      TechnicianAllocation.joins(:visit).where(visits: { status: "completed", finished_at: range }).group(:membership_id).count
    end

    def logged_time
      TimeEntry.where(started_at: range).group(:membership_id)
        .pluck(:membership_id, Arel.sql("sum(minutes)"), Arel.sql("sum(labor_cost)"))
        .to_h { |id, minutes, cost| [id, [minutes, cost]] }
    end
  end
end
