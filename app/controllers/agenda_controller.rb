# frozen_string_literal: true

class AgendaController < TenantController
  def index
    authorize Visit, :index?
    @date = parse_date(params[:data])
    @mode = params[:visao] == "semana" ? "semana" : "dia"
    technicians = policy_scope(current_organization.memberships.technicians, policy_scope_class: VisitPolicy::Scope)
    allocations = policy_scope(current_organization.technician_allocations)
    @agenda = Scheduling::AgendaQuery.new(technicians_scope: technicians, allocations_scope: allocations, date: @date,
      mode: @mode, membership_id: params[:tecnico].presence)
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    Time.zone.today
  end
end
