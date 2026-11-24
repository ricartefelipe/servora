# frozen_string_literal: true

# Scheduling actions on a work order's visits.
class VisitsController < TenantController
  before_action :load_work_order
  before_action :load_visit, except: %i[new create suggestions]

  def new
    authorize Visit, :create?
    @starts_at = default_start
  end

  def edit
    authorize @visit, :manage?
  end

  def create
    authorize Visit, :create?
    attributes = params.expect(visit: [:date, :start_time, :duration_minutes, :travel_minutes, :team_id, :notes,
                                       { technician_ids: [] }])
    starts_at, ends_at = period_from(attributes)
    Scheduling::ScheduleVisit.new(work_order: @work_order, starts_at:, ends_at:, technicians: selected_technicians(attributes),
      actor: current_membership, team: selected_team(attributes), travel_minutes: attributes[:travel_minutes].presence,
      notes: attributes[:notes]).call
    redirect_to agenda_index_path(data: starts_at.to_date.iso8601),
      notice: "Visita agendada para #{l(starts_at, format: :short)}.", status: :see_other
  rescue Servora::RuleViolation => e
    @starts_at = starts_at || default_start
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_content
  end

  # Turbo Frame with ranked technicians for the chosen slot.
  def suggestions
    authorize Visit, :create?
    starts_at, ends_at = period_from(params.permit(:date, :start_time, :duration_minutes))
    @result = Scheduling::SuggestTechnicians.new(work_order: @work_order, starts_at:, ends_at:).call
    @technicians = tenant_relation(Membership).includes(:user).where(id: @result.ranked.map(&:id)).index_by(&:id)
    render layout: false
  rescue Servora::RuleViolation, ArgumentError
    @result = nil
    render layout: false
  end

  def update
    authorize @visit, :manage?
    attributes = params.expect(visit: %i[date start_time duration_minutes reason])
    starts_at, ends_at = period_from(attributes)
    Scheduling::RescheduleVisit.new(visit: @visit, starts_at:, ends_at:, actor: current_membership,
      reason: attributes[:reason]).call
    redirect_to work_order_path(@work_order), notice: "Visita reagendada.", status: :see_other
  rescue Servora::RuleViolation => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_content
  end

  def start
    authorize @visit, :execute?
    Visits::Start.new(visit: @visit, actor: current_membership).call
    redirect_to execution_path, notice: "Visita iniciada.", status: :see_other
  end

  def finish
    authorize @visit, :execute?
    finish_params = params.expect(finish: %i[outcome_note needs_return])
    Visits::Finish.new(visit: @visit, actor: current_membership, outcome_note: finish_params[:outcome_note],
      needs_return: finish_params[:needs_return] == "1").call
    redirect_to execution_path, notice: "Visita finalizada. A ordem segue aberta até a conclusão formal.",
      status: :see_other
  end

  def cancel
    authorize @visit, :manage?
    cancellation = params.expect(cancellation: %i[reason no_show])
    Visits::Cancel.new(visit: @visit, actor: current_membership, reason: cancellation[:reason],
      no_show: cancellation[:no_show] == "1").call
    redirect_to work_order_path(@work_order), notice: "Visita cancelada e agenda liberada.", status: :see_other
  end

  rescue_from Servora::RuleViolation do |error|
    redirect_to work_order_path(@work_order), alert: error.message, status: :see_other
  end

  private

  # Field area actions return to the mobile execution view.
  def execution_path
    params[:origem] == "campo" ? field_work_order_path(@work_order) : work_order_path(@work_order)
  end

  def load_work_order
    @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:organization, :assignments, service_type: :skills)
      .find(params.expect(:work_order_id))
    authorize @work_order, :show?
  end

  def load_visit
    @visit = tenant_relation(Visit).includes(:work_order, allocations: { membership: %i[user work_schedules] })
      .where(work_order_id: @work_order.id).find(params.expect(:id))
  end

  def period_from(attributes)
    starts_at = Time.zone.parse("#{attributes[:date]} #{attributes[:start_time]}")
    raise Scheduling::ScheduleVisit::InvalidRequest, "Informe data e horário válidos." unless starts_at

    duration = Integer(attributes[:duration_minutes].presence || 60, exception: false).to_i.clamp(15, 720)
    [starts_at, starts_at + duration.minutes]
  end

  def selected_technicians(attributes)
    ids = Array(attributes[:technician_ids]).compact_blank
    team = selected_team(attributes)
    ids += team.team_members.map(&:membership_id) if team
    tenant_relation(Membership).includes(:user, :work_schedules).where(id: ids.uniq).to_a
  end

  def selected_team(attributes)
    return nil if attributes[:team_id].blank?

    @selected_team ||= tenant_relation(Team).active.includes(:team_members).find(attributes[:team_id])
  end

  def default_start
    1.day.from_now.change(hour: 9)
  end
end
