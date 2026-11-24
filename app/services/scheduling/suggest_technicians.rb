# frozen_string_literal: true

module Scheduling
  # Gathers candidate data from the database and delegates the ranking to
  # Scheduling::Suggestion (pure, deterministic).
  class SuggestTechnicians
    Result = Data.define(:ranked, :others)

    def initialize(work_order:, starts_at:, ends_at:, travel_minutes: nil)
      @work_order = work_order
      @interval = Interval.for_visit(starts_at:, ends_at:,
        travel_minutes: travel_minutes || work_order.organization.travel_buffer_minutes)
    end

    def call
      technicians = Membership.technicians.includes(:user, :skills, :work_schedules).to_a
      busy = TechnicianAllocation.active.overlapping(@interval).where(membership_id: technicians.map(&:id))
        .distinct.pluck(:membership_id)
      booked = booked_minutes(technicians)
      candidates = technicians.map { |m| candidate(m, busy, booked) }
      ranked = Suggestion.rank(candidates, required_skills:)
      others = (candidates - ranked).map { |c| [c, Suggestion.reasons(c, required_skills:)] }
      Result.new(ranked:, others:)
    end

    private

    def required_skills
      @required_skills ||= @work_order.service_type ? @work_order.service_type.skills.map(&:name) : []
    end

    def candidate(membership, busy, booked)
      Suggestion::Candidate.new(
        id: membership.id, name: membership.user.name, skills: membership.skills.map(&:name),
        available: busy.exclude?(membership.id),
        within_hours: membership.working_hours.fits?(@interval.starts_at.in_time_zone,
          (@interval.ends_at - (@work_order.organization.travel_buffer_minutes * 60)).in_time_zone),
        booked_minutes: booked.fetch(membership.id, 0)
      )
    end

    def booked_minutes(technicians)
      day = @interval.starts_at.in_time_zone.all_day
      TechnicianAllocation.active.where(kind: "visit", membership_id: technicians.map(&:id))
        .where("period && tstzrange(?, ?, '[)')", day.begin, day.end)
        .group_by(&:membership_id)
        .transform_values { |allocations| allocations.sum { |a| ((a.ends_at - a.starts_at) / 60).round } }
    end
  end
end
