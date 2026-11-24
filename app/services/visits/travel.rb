# frozen_string_literal: true

module Visits
  # Technician leaves for the site: the visit is "em deslocamento" until it is
  # started on arrival. The work order stays as it is (the SLA first response
  # is the start of the visit, not the trip).
  #
  # at is when the technician tapped the button; replays from the offline queue
  # carry the device time, kept between the visit creation and now so a wrong
  # device clock cannot move the record into the future.
  class Travel
    def initialize(visit:, actor:, at: Time.current)
      @visit = visit
      @actor = actor
      @at = at
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @visit.lock!
        now = Time.current
        at = @at.clamp([@visit.created_at, now].min, now)
        Transition.apply!(@visit, to: "traveling", actor: @actor, travel_started_at: at)
        AuditEvent.record!(action: "visit.travel_started", auditable: @visit.work_order,
          changes: { visit_id: @visit.id, travel_started_at: at })
        @visit
      end
    end
  end
end
