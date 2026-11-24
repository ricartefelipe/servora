# frozen_string_literal: true

# Business hours, SLA targets and national holidays for both demonstration
# organizations. Idempotent: existing configuration is kept.
module Seeds
  SLA_TARGETS = {
    "urgent" => [60, 240, false], "high" => [120, 480, true], "normal" => [240, 960, true], "low" => [480, 2400, true]
  }.freeze
  SHIFTS_SLA = [[480, 720], [780, 1080]].freeze
  HOLIDAYS = {
    "2026-01-01" => "Confraternização Universal", "2026-04-03" => "Sexta-feira Santa", "2026-04-21" => "Tiradentes",
    "2026-05-01" => "Dia do Trabalho", "2026-09-07" => "Independência do Brasil", "2026-10-12" => "Nossa Senhora Aparecida",
    "2026-11-02" => "Finados", "2026-11-15" => "Proclamação da República", "2026-11-20" => "Dia da Consciência Negra",
    "2026-12-25" => "Natal", "2027-01-01" => "Confraternização Universal", "2027-03-26" => "Sexta-feira Santa",
    "2027-04-21" => "Tiradentes", "2027-05-01" => "Dia do Trabalho", "2027-09-07" => "Independência do Brasil",
    "2027-10-12" => "Nossa Senhora Aparecida", "2027-11-02" => "Finados", "2027-11-15" => "Proclamação da República",
    "2027-11-20" => "Dia da Consciência Negra", "2027-12-25" => "Natal"
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

Seeds.sla("a")
Seeds.sla("b")
puts "Expediente, prazos de SLA e feriados prontos."
