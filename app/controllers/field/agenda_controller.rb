# frozen_string_literal: true

module Field
  # "Minha agenda": the technician's visits for the next days and assigned
  # work orders without a visit.
  class AgendaController < TenantController
    layout "field"

    DAYS = 7

    def show
      authorize :field, :show?
      zone = current_organization.zone
      @today = Time.current.in_time_zone(zone).to_date
      @visits_by_day = visits(zone).group_by { |visit| visit.scheduled_start.in_time_zone(zone).to_date }
      @unscheduled = assigned_orders.where.not(id: Visit.upcoming.select(:work_order_id)).order(:requested_at).limit(20)
    end

    private

    def visits(zone)
      range = @today.in_time_zone(zone)...(@today + DAYS).in_time_zone(zone)
      Visit.joins(:allocations).active_allocations.where(technician_allocations: { membership_id: current_membership.id })
        .where(scheduled_start: range, status: %w[scheduled in_progress])
        .includes(work_order: %i[customer service_location]).order(:scheduled_start).distinct.to_a
    end

    def assigned_orders
      policy_scope(tenant_relation(WorkOrder)).open_work.where(id: WorkOrderAssignment.where(membership_id: current_membership.id)
        .select(:work_order_id)).includes(:customer, :service_location)
    end
  end
end
