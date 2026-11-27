# frozen_string_literal: true

require_relative "organizations"
require_relative "customers"
require_relative "story_clock"
require_relative "demo_activity/office_actions"
require_relative "demo_activity/quote_actions"
require_relative "demo_activity/field_actions"
require_relative "demo_activity/story_records"
require_relative "demo_activity/living_checks"
require_relative "demo_activity/living"
require_relative "demo_activity/timeline"
require_relative "demo_activity/clima_norte_pool"
require_relative "demo_activity/routine_book"
require_relative "demo_activity/routine_catalog"
require_relative "demo_activity/routine_jobs"
require_relative "demo_activity/history_plan"
require_relative "demo_activity/history"
require_relative "demo_activity/clima_norte"
require_relative "demo_activity/predial_sul"

module Seeds
  # History of the demonstration organizations, recorded through the domain
  # use cases relative to the run instant (see Seeds::StoryClock and
  # DemoActivity::Timeline). Enabled by default only in development; the
  # public demonstration sets SEED_DEMO_ACTIVITY=1.
  #
  # Loaded by db/seeds/10_demo_activity.rb, which records the stories, and by
  # Demo::AdvanceStoryJob, which applies today's events as their time comes
  # (DemoActivity::Living): both read the same definitions.
  module DemoActivity
    STORIES = { "a" => "ClimaNorte", "b" => "PredialSul" }.freeze

    module_function

    def enabled? = StoryClock.enabled?

    # { "a" => true/false, "b" => true/false } (false: already recorded).
    def call
      STORIES.to_h { |key, story| [key, const_get(story).new(key).call] }
    end

    # { "a" => [[instant, action, order key], ...], "b" => [...] }: the events
    # of today applied now (empty for a story not recorded yet, recorded on
    # another day, or with nothing due).
    def advance(now: Time.current)
      STORIES.to_h { |key, story| [key, const_get(story).new(key).advance(now:)] }
    end
  end
end
