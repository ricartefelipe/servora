# frozen_string_literal: true

class AbsencesController < TenantController
  def index
    authorize TechnicianAllocation
    @absences = policy_scope(current_organization.technician_allocations).active.where(kind: "absence")
      .where("upper(period) >= ?", Time.current).includes(membership: :user).order(Arel.sql("lower(period)"))
    @technicians = current_organization.memberships.technicians.includes(:user).ordered
  end

  def create
    authorize TechnicianAllocation
    absence = params.expect(absence: %i[membership_id starts_at ends_at reason])
    membership = tenant_relation(Membership).technicians.find(absence[:membership_id])
    Scheduling::RegisterAbsence.new(membership:, starts_at: Time.zone.parse(absence[:starts_at].to_s),
      ends_at: Time.zone.parse(absence[:ends_at].to_s), reason: absence[:reason], actor: current_membership).call
    redirect_to absences_path, notice: "Ausência registrada.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to absences_path, alert: e.message, status: :see_other
  end

  def destroy
    allocation = tenant_relation(TechnicianAllocation).find(params.expect(:id))
    authorize allocation
    allocation.update!(status: "released", released_at: Time.current)
    AuditEvent.record!(action: "absence.released", auditable: allocation.membership, changes: { reason: allocation.reason })
    redirect_to absences_path, notice: "Ausência removida.", status: :see_other
  end
end
