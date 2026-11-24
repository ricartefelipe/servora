# frozen_string_literal: true

module Scheduling
  # Moves a scheduled visit. Old allocations are released and new ones created
  # in the same savepoint: on conflict, the original reservation stays intact.
  class RescheduleVisit
    class NotReschedulable < Servora::RuleViolation; end

    def initialize(visit:, starts_at:, ends_at:, actor:, reason: nil, enforce_working_hours: true)
      @visit = visit
      @starts_at = starts_at
      @ends_at = ends_at
      @actor = actor
      @reason = reason
      @enforce_working_hours = enforce_working_hours
    end

    def call
      raise NotReschedulable, "Somente visitas agendadas podem ser reagendadas." unless @visit.scheduled?

      technicians = @visit.allocations.active.includes(membership: %i[user work_schedules]).map(&:membership)
      interval = Interval.for_visit(starts_at: @starts_at, ends_at: @ends_at, travel_minutes: @visit.travel_minutes)
      check_hours!(technicians)
      ActiveRecord::Base.transaction(requires_new: true) { move!(technicians, interval) }
      @visit
    rescue ArgumentError
      raise ScheduleVisit::InvalidRequest, "Informe início e término válidos."
    rescue ActiveRecord::ExclusionViolation
      Servora::Metrics.increment(:schedule_conflicts_total, { source: "reschedule" })
      raise ScheduleVisit::Conflict, ConflictDetector.message(technicians.map(&:id), interval)
    end

    private

    def move!(technicians, interval)
      previous = [@visit.scheduled_start, @visit.scheduled_end]
      release_current!
      @visit.update!(scheduled_start: @starts_at, scheduled_end: @ends_at)
      technicians.sort_by(&:id).each do |technician|
        @visit.allocations.create!(organization_id: @visit.organization_id, membership: technician, kind: "visit",
          period: interval.to_range)
      end
      record(previous)
    end

    def check_hours!(technicians)
      return unless @enforce_working_hours

      outside = technicians.reject { |m| m.working_hours.fits?(@starts_at.in_time_zone, @ends_at.in_time_zone) }
      return unless outside.any?

      raise ScheduleVisit::InvalidRequest, "Fora do horário de trabalho de #{outside.map do |m|
        m.user.name
      end.join(", ")}."
    end

    def release_current!
      @visit.allocations.active.update_all(status: "released", released_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def record(previous)
      note = "Reagendada de #{I18n.l(previous.first.in_time_zone,
        format: :short)} para #{I18n.l(@starts_at.in_time_zone, format: :short)}"
      @visit.transitions.create!(organization_id: @visit.organization_id, from_status: "scheduled", to_status: "scheduled",
        reason: [note, @reason].compact_blank.join(". "), actor_membership_id: @actor.id, actor_label: @actor.user.name)
      AuditEvent.record!(action: "visit.rescheduled", auditable: @visit.work_order, changes: { visit_id: @visit.id, note: })
    end
  end
end
