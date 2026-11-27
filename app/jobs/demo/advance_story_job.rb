# frozen_string_literal: true

module Demo
  # Keeps the public demonstration alive during the day: applies the events of
  # today's story whose time has come since the daily seeding (a technician on
  # the way, a visit finished, a Pix received...), from the same definitions
  # the seed used (db/seeds/support/demo_activity, see DemoActivity::Living).
  #
  # Scheduled every 5 minutes by config/recurring.yml only in demo mode, and a
  # no-op anywhere else: it acts only with SERVORA_DEMO=1 (Servora::Demo) and
  # SEED_DEMO_ACTIVITY=1 on the worker, so an instance serving customers never
  # writes demonstration data, even if the task were scheduled by mistake.
  #
  # The story is applied with the clock moved to each event's instant
  # (travel_to), which changes the time of the whole process: the job has its
  # own "demo" queue, served in demo mode by a single-thread worker process
  # that runs nothing else (config/queue.yml), so no other job, and no
  # heartbeat of another process, ever reads that clock.
  class AdvanceStoryJob < ApplicationJob
    queue_as :demo

    STORY = Rails.root.join("db/seeds/support/demo_activity").to_s

    # The story code is loaded only in demo mode.
    def self.enabled?
      return false unless Servora::Demo.enabled?

      require STORY
      Seeds::DemoActivity.enabled?
    end

    def perform
      return unless self.class.enabled?

      applied = Seeds::DemoActivity.advance
      return if applied.values.all?(&:empty?)

      Rails.logger.info(Servora::StructuredLog.line(event: "demo.story_advanced",
        applied: applied.transform_values { |events| events.map { |at, action, _| "#{at.strftime("%H:%M")} #{action}" } }))
    end
  end
end
