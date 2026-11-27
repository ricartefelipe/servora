# frozen_string_literal: true

module Field
  # "Minha agenda": the technician's visits for the next days, the visits
  # already finished today and assigned work orders without a visit.
  class AgendaController < TenantController
    layout "field"

    DAYS = 7

    def show
      authorize :field, :show?
      zone = current_organization.zone
      @today = Time.current.in_time_zone(zone).to_date
      @visits_by_day = visits(zone).group_by { |visit| visit.scheduled_start.in_time_zone(zone).to_date }
      @completed_today = completed_today(zone)
      @unscheduled = assigned_orders.where.not(id: Visit.upcoming.select(:work_order_id)).order(:requested_at).limit(20)
    end

    private

    def visits(zone)
      range = @today.in_time_zone(zone)...(@today + DAYS).in_time_zone(zone)
      own_visits.where(scheduled_start: range, status: Visits::OPEN)
        .includes(work_order: %i[customer service_location]).order(:scheduled_start).distinct.to_a
    end

    # Visits this technician finished today (finishing keeps the allocation active).
    def completed_today(zone)
      own_visits.where(status: "completed", finished_at: @today.in_time_zone(zone)...(@today + 1).in_time_zone(zone))
        .includes(work_order: :customer).order(:finished_at).distinct.to_a
    end

    def own_visits
      Visit.joins(:allocations).active_allocations.where(technician_allocations: { membership_id: current_membership.id })
    end

    def assigned_orders
      policy_scope(tenant_relation(WorkOrder)).open_work.where(id: WorkOrderAssignment.where(membership_id: current_membership.id)
        .select(:work_order_id)).includes(:customer, :service_location)
    end
  end
end
