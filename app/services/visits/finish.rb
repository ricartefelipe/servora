# frozen_string_literal: true

module Visits
  # Ends a visit. The work order is NOT completed here: formal completion is a
  # separate decision. Finishing early frees the rest of the reservation
  # (keeping the travel buffer after the actual end).
  class Finish
    def initialize(visit:, actor:, outcome_note: nil, needs_return: false, at: Time.current)
      @visit = visit
      @actor = actor
      @outcome_note = outcome_note
      @needs_return = needs_return
      @at = at
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @visit.lock!
        Transition.apply!(@visit, to: "completed", actor: @actor, finished_at: @at, outcome_note: @outcome_note,
          needs_return: @needs_return)
        shrink_allocations
        Outbox::Publisher.publish!(event_type: "visit.finished", aggregate: @visit, dedup_key: "visit.finished:#{@visit.id}")
        @visit
      end
    end

    private

    def shrink_allocations
      @visit.allocations.active.find_each do |allocation|
        new_end = [@at, allocation.starts_at + 60].max + (@visit.travel_minutes * 60)
        next unless new_end < allocation.ends_at

        allocation.update!(period: allocation.starts_at...new_end)
      end
    end
  end
end
