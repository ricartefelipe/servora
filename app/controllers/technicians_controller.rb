# frozen_string_literal: true

# Technician profile for dispatching: skills and weekly working hours.
class TechniciansController < TenantController
  before_action :load_technician, only: %i[edit update]

  def index
    authorize Visit, :create?
    @technicians = policy_scope(current_organization.memberships.technicians, policy_scope_class: VisitPolicy::Scope)
      .includes(:user, :skills, :work_schedules).ordered
    @teams = current_organization.teams.includes(members: :user).alphabetical
  end

  def edit
    @skills = current_organization.skills.alphabetical
  end

  def update
    attributes = params.expect(technician: [{ skill_ids: [] }, :new_skill, { schedules: [%i[weekday start end]] }])
    Scheduling::UpdateTechnicianProfile.new(membership: @technician, skill_ids: attributes[:skill_ids],
      new_skill: attributes[:new_skill], schedules: attributes[:schedules]).call
    redirect_to technicians_path, notice: "Perfil de #{@technician.user.name} atualizado.", status: :see_other
  rescue Servora::RuleViolation, ActiveRecord::RecordInvalid => e
    redirect_to edit_technician_path(@technician), alert: e.message, status: :see_other
  end

  private

  def load_technician
    @technician = tenant_relation(Membership).technicians.includes(:user, :skills, :work_schedules).find(params.expect(:id))
    authorize @technician, :update?, policy_class: TechnicianProfilePolicy
  end
end
