# frozen_string_literal: true

module Scheduling
  # Schedules a visit and reserves every technician atomically: all
  # allocations are inserted inside one savepoint, so a conflict on any member
  # (detected by PostgreSQL's exclusion constraint) leaves no partial team
  # reservation behind. Technicians are processed in id order to keep a
  # consistent lock order between concurrent requests.
  class ScheduleVisit
    SCHEDULABLE_STATES = %w[approved scheduled in_progress waiting_parts waiting_customer reopened].freeze

    class Conflict < Servora::RuleViolation; end
    class InvalidRequest < Servora::RuleViolation; end

    def initialize(work_order:, starts_at:, ends_at:, technicians:, actor:, team: nil, travel_minutes: nil, notes: nil,
                   enforce_working_hours: true)
      @work_order = work_order
      @starts_at = starts_at
      @ends_at = ends_at
      @technicians = technicians.uniq(&:id).sort_by(&:id)
      @actor = actor
      @team = team
      @travel_minutes = (travel_minutes || work_order.organization.travel_buffer_minutes).to_i
      @notes = notes
      @enforce_working_hours = enforce_working_hours
    end

    def call
      interval = build_interval
      validate!(interval)
      reserve(interval)
    rescue ActiveRecord::ExclusionViolation
      Servora::Metrics.increment(:schedule_conflicts_total, { source: "schedule" })
      raise Conflict, ConflictDetector.message(@technicians.map(&:id), interval)
    end

    private

    def build_interval
      Interval.for_visit(starts_at: @starts_at, ends_at: @ends_at, travel_minutes: @travel_minutes)
    rescue ArgumentError
      raise InvalidRequest, "Informe início e término válidos: o término deve ser posterior ao início."
    end

    def validate!(_interval)
      unless schedulable?
        raise InvalidRequest,
          "A ordem #{@work_order.number} não pode ser agendada (#{@work_order.status_label})."
      end
      raise InvalidRequest, "Selecione ao menos um técnico." if @technicians.empty?
      raise InvalidRequest, "Somente técnicos ativos podem ser agendados." unless technicians_active?

      validate_working_hours! if @enforce_working_hours
    end

    def technicians_active? = @technicians.all? { |m| m.active? && m.technician? }

    def validate_working_hours!
      outside = @technicians.reject { |m| m.working_hours.fits?(@starts_at.in_time_zone, @ends_at.in_time_zone) }
      return if outside.empty?

      raise InvalidRequest, "Fora do horário de trabalho de #{outside.map { |m| m.user.name }.join(", ")}."
    end

    def schedulable? = SCHEDULABLE_STATES.include?(@work_order.status)

    def reserve(interval)
      ActiveRecord::Base.transaction(requires_new: true) do
        @work_order.lock!
        visit = create_visit
        @technicians.each do |technician|
          visit.allocations.create!(organization_id: visit.organization_id, membership: technician, kind: "visit",
            period: interval.to_range)
          WorkOrders::Assign.new(work_order: @work_order, membership: technician).call
        end
        finish(visit)
      end
    end

    def create_visit
      visit = @work_order.visits.create!(organization_id: @work_order.organization_id, scheduled_start: @starts_at,
        scheduled_end: @ends_at, travel_minutes: @travel_minutes, team: @team, notes: @notes, scheduled_by: @actor)
      visit.transitions.create!(organization_id: visit.organization_id, to_status: "scheduled", actor_membership_id: @actor.id,
        actor_label: @actor.user.name)
      visit
    end

    def finish(visit)
      if WorkOrders::States.allowed?(@work_order.status, "scheduled") && @work_order.status != "in_progress"
        WorkOrders::Transition.new(work_order: @work_order, to: "scheduled", actor: @actor).call
      end
      AuditEvent.record!(action: "visit.scheduled", auditable: @work_order,
        changes: { visit_id: visit.id, starts_at: @starts_at, technicians: @technicians.map(&:id) })
      Outbox::Publisher.publish!(event_type: "visit.scheduled", aggregate: visit, dedup_key: "visit.scheduled:#{visit.id}")
      visit
    end
  end
end
