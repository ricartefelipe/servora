# frozen_string_literal: true

module Scheduling
  # Absences use the same exclusion constraint as visits: an absence cannot
  # overlap a scheduled visit (and vice versa) for the same technician.
  class RegisterAbsence
    def initialize(membership:, starts_at:, ends_at:, reason:, actor:)
      @membership = membership
      @starts_at = starts_at
      @ends_at = ends_at
      @reason = reason.to_s.strip
      @actor = actor
    end

    def call
      raise ScheduleVisit::InvalidRequest, "Informe o motivo da ausência." if @reason.blank?

      interval = Interval.new(starts_at: @starts_at, ends_at: @ends_at)
      allocation = ActiveRecord::Base.transaction(requires_new: true) do
        TechnicianAllocation.create!(organization_id: @membership.organization_id, membership: @membership, kind: "absence",
          reason: @reason, period: interval.to_range)
      end
      AuditEvent.record!(action: "absence.registered", auditable: @membership, changes: { reason: @reason })
      allocation
    rescue ArgumentError
      raise ScheduleVisit::InvalidRequest, "O término da ausência deve ser posterior ao início."
    rescue ActiveRecord::ExclusionViolation
      Servora::Metrics.increment(:schedule_conflicts_total, { source: "absence" })
      raise ScheduleVisit::Conflict, ConflictDetector.message([@membership.id], interval)
    end
  end
end
