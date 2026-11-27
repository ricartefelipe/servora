# frozen_string_literal: true

require "rails_helper"
require_relative "demo_story_helpers"

# The public demonstration is re-seeded every day before dawn, and the seed
# may also run at any other instant. Whatever the instant, the story is
# recorded and nothing dated after it has happened: today's visits are done,
# under way or still scheduled exactly as their times say. A shorter history
# without the routine work (no technician in HistoryPlan) keeps each load cheap;
# the full story is covered by demo_activity_seed_spec.rb and the rest of the
# day by demo_living_story_spec.rb.
RSpec.describe "Demonstration activity at different instants" do
  include DemoStoryHelpers

  def business_day?(date) = date.on_weekday? && !Seeds::HOLIDAYS.key?(date.iso8601)

  before do
    allow(Seeds::StoryClock).to receive(:history_days).and_return(6)
    stub_const("Seeds::DemoActivity::HistoryPlan::TECHNICIANS", [])
    enable_demo_activity
  end

  # instant => [today's agenda, orders waiting for parts, open or approved
  # orders] (scheduled visits of the next business day are never executed).
  # Renato's portal request waits for triage until 10:15 and is attended by
  # Diego before lunch; the installation assessment is scheduled at 14:40.
  {
    "a Saturday mid-morning (on-call schedule)" => [[2026, 11, 28, 11, 0], {
      "Diego" => %w[completed traveling scheduled], "Eduarda" => %w[completed scheduled],
      "Fábio" => %w[in_progress scheduled]
    }, 1, [%w[email low]]],
    "Christmas 2026 (a holiday Friday)" => [[2026, 12, 25, 10, 0], {
      "Diego" => %w[completed scheduled], "Eduarda" => %w[completed scheduled], "Fábio" => %w[traveling scheduled]
    }, 1, [%w[portal high], %w[email low]]],
    "the first day of a month at 03:00" => [[2026, 12, 1, 3, 0], {
      "Diego" => %w[scheduled scheduled], "Eduarda" => %w[scheduled scheduled], "Fábio" => %w[scheduled scheduled]
    }, 1, [%w[portal high], %w[email low]]],
    "a weekday at 15:00" => [[2026, 12, 2, 15, 0], {
      "Diego" => %w[completed completed in_progress], "Eduarda" => %w[completed scheduled],
      "Fábio" => %w[completed scheduled]
    }, 1, []]
  }.each do |moment, (instant, today, waiting_parts, waiting)|
    it "records only what has happened by #{moment}" do
      now = local(*instant)
      travel_to(now)

      expect { load_seeds }.to output(/Atividade de demonstração registrada/).to_stdout
      in_tenant(organization_id("a")) do
        aggregate_failures do
          expect(agenda(now.to_date)).to eq(today)
          expect(Visit.where(scheduled_start: now..).where(status: %w[in_progress completed]).count).to eq(0)
          expect(recorded_after(now)).to be_empty
          expect(WorkOrder.where(status: "waiting_parts").count).to eq(waiting_parts)
          expect(WorkOrder.where(status: %w[open approved]).pluck(:origin, :priority)).to match_array(waiting)
          expect(StockMovement.minimum(:occurred_at)).to eq(Seeds::StoryClock.origin(from: now))
          # Payments written for today are received on the next business day
          # when today is a weekend or a holiday.
          expect(Payment.pluck(:paid_at).map { |at| in_zone(at).to_date }).to all(satisfy { |date| business_day?(date) })
        end
      end
    end
  end
end
