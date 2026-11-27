# frozen_string_literal: true

# Business hours, SLA targets and national holidays for both demonstration
# organizations. Idempotent: existing configuration is kept. The hours and
# holidays are Seeds::SHIFTS_SLA and Seeds::HOLIDAYS (support/story_clock.rb).
require_relative "support/story_clock"

module Seeds
  SLA_TARGETS = {
    "urgent" => [60, 240, false], "high" => [120, 480, true], "normal" => [240, 960, true], "low" => [480, 2400, true]
  }.freeze

  def self.sla(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      seed_business_hours(organization_id)
      SLA_TARGETS.each do |priority, (response, resolution, business_only)|
        SlaPolicy.find_or_create_by!(organization_id:, priority:) do |policy|
          policy.assign_attributes(first_response_minutes: response, resolution_minutes: resolution,
            business_hours_only: business_only)
        end
      end
      HOLIDAYS.each { |date, name| Holiday.find_or_create_by!(organization_id:, date: Date.iso8601(date)) { |h| h.name = name } }
    end
  end

  def self.seed_business_hours(organization_id)
    return if BusinessHour.exists?

    (1..5).each do |weekday|
      SHIFTS_SLA.each do |start_minute, end_minute|
        BusinessHour.create!(organization_id:, weekday:, start_minute:, end_minute:)
      end
    end
  end
end

Seeds::StoryClock.at_origin do
  Seeds.sla("a")
  Seeds.sla("b")
end
puts "Expediente, prazos de SLA e feriados prontos."
