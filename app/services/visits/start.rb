# frozen_string_literal: true

module Visits
  # Technician arrives and starts the visit. The work order moves to
  # "in progress" (its first start is also the SLA first response).
  class Start
    def initialize(visit:, actor:, at: Time.current)
      @visit = visit
      @actor = actor
      @at = at
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @visit.lock!
        work_order = @visit.work_order.lock!
        Transition.apply!(@visit, to: "in_progress", actor: @actor, started_at: @at)
        if work_order.status != "in_progress" && WorkOrders::States.allowed?(work_order.status, "in_progress")
          WorkOrders::Transition.new(work_order:, to: "in_progress", actor: @actor, at: @at).call
        end
        Outbox::Publisher.publish!(event_type: "visit.started", aggregate: @visit, dedup_key: "visit.started:#{@visit.id}")
        @visit
      end
    end
  end
end
