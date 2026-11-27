# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/support/demo_activity").to_s

# The behaviour of the living story itself (what is applied, when, and how
# visitor actions are respected) is covered by spec/database/demo_living_story_spec.rb.
RSpec.describe Demo::AdvanceStoryJob do
  def recurring_tasks(environment)
    with_environment(environment) do
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).fetch("production")
    end
  end

  def workers(environment)
    with_environment(environment) do
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/queue.yml")).fetch("production").fetch("workers")
    end
  end

  before { allow(Seeds::DemoActivity).to receive(:advance).and_call_original }

  it "does nothing outside demo mode", demo_mode: false do
    with_environment("SEED_DEMO_ACTIVITY" => "1") do
      expect(described_class.enabled?).to be(false)
      described_class.perform_now
    end

    expect(Seeds::DemoActivity).not_to have_received(:advance)
  end

  it "does nothing in demo mode when the story is disabled", :demo_mode do
    with_environment("SEED_DEMO_ACTIVITY" => "0") do
      expect(described_class.enabled?).to be(false)
      described_class.perform_now
    end

    expect(Seeds::DemoActivity).not_to have_received(:advance)
  end

  it "advances today's story in demo mode and logs what it applied", :demo_mode do
    with_environment("SEED_DEMO_ACTIVITY" => "1") do
      at = Time.zone.local(2026, 12, 2, 9, 50)
      allow(Seeds::DemoActivity).to receive(:advance)
        .and_return("a" => [[at, :pay, :c3]], "b" => [])
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.perform_now

      expect(Seeds::DemoActivity).to have_received(:advance)
      expect(Rails.logger).to have_received(:info).with(a_string_including("demo.story_advanced", "09:50 pay"))
    end
  end

  it "is scheduled every 5 minutes only in demo mode with the story enabled" do
    expect(recurring_tasks("SERVORA_DEMO" => "1", "SEED_DEMO_ACTIVITY" => "1")["demo_story_advance"])
      .to include("class" => "Demo::AdvanceStoryJob", "queue" => "demo", "schedule" => "every 5 minutes")
    expect(recurring_tasks("SERVORA_DEMO" => "0", "SEED_DEMO_ACTIVITY" => "1")).not_to have_key("demo_story_advance")
    expect(recurring_tasks("SERVORA_DEMO" => "1", "SEED_DEMO_ACTIVITY" => "0")).not_to have_key("demo_story_advance")
    expect(recurring_tasks("SERVORA_DEMO" => "1", "SEED_DEMO_ACTIVITY" => nil)).not_to have_key("demo_story_advance")
  end

  # travel_to moves the clock of the whole process: the job runs alone in a
  # single-thread worker of its own, which no other queue shares.
  it "runs on its own queue, served in demo mode by a dedicated single-thread worker" do
    expect(described_class.queue_name).to eq("demo")
    expect(workers("SERVORA_DEMO" => "1")).to include(include("queues" => ["demo"], "threads" => 1, "processes" => 1))
    expect(workers("SERVORA_DEMO" => "1").pluck("queues").flatten.count("demo")).to eq(1)
    expect(workers("SERVORA_DEMO" => "0").flat_map { |worker| worker["queues"] }).not_to include("demo")
  end
end
