# frozen_string_literal: true

# SLA configuration screen: targets per priority (hours and minutes) and the
# weekly business hours (up to two intervals per weekday, "HH:MM").
class SlaSettingsForm
  include ActiveModel::Model

  TIME_FORMAT = /\A(\d{1,2}):(\d{2})\z/

  attr_reader :policies, :hours

  def self.load
    policies = SlaPolicy.all.index_by(&:priority)
    hours = BusinessHour.order(:start_minute).group_by(&:weekday)
    new(
      policies: WorkOrder::PRIORITIES.keys.index_with { |priority| policy_fields(policies[priority]) },
      hours: (0..6).to_h { |weekday| [weekday.to_s, hour_fields(hours.fetch(weekday, []))] }
    )
  end

  def self.policy_fields(policy)
    return { "enabled" => "0", "warning_percent" => "80", "business_hours_only" => "1" } unless policy

    { "enabled" => "1", "first_response" => duration(policy.first_response_minutes),
      "resolution" => duration(policy.resolution_minutes), "business_hours_only" => policy.business_hours_only ? "1" : "0",
      "warning_percent" => policy.warning_percent.to_s }
  end

  def self.hour_fields(intervals)
    fields = {}
    intervals.first(2).each_with_index do |interval, index|
      fields["start#{index + 1}"] = BusinessHour.clock(interval.start_minute)
      fields["end#{index + 1}"] = BusinessHour.clock(interval.end_minute)
    end
    fields
  end

  def self.duration(minutes) = BusinessHour.clock(minutes)

  def initialize(policies: {}, hours: {})
    super()
    @policies = policies.to_h.transform_values(&:to_h)
    @hours = hours.to_h.transform_values(&:to_h)
  end

  # [{ priority:, first_response_minutes:, … }] for enabled priorities.
  def policy_rows
    WorkOrder::PRIORITIES.keys.filter_map do |priority|
      fields = @policies.fetch(priority, {})
      next unless fields["enabled"] == "1"

      { priority:, first_response_minutes: minutes!(fields["first_response"], priority, "primeira resposta"),
        resolution_minutes: minutes!(fields["resolution"], priority, "resolução"),
        business_hours_only: fields["business_hours_only"] == "1", warning_percent: fields["warning_percent"].to_i }
    end
  end

  # [[weekday, start_minute, end_minute], …]
  def hour_rows
    (0..6).flat_map do |weekday|
      fields = @hours.fetch(weekday.to_s, {})
      (0..1).filter_map do |index|
        start = fields["start#{index + 1}"]
        finish = fields["end#{index + 1}"]
        next if start.blank? && finish.blank?

        [weekday, clock!(start), clock!(finish, end_of_day: true)]
      end
    end
  end

  private

  def minutes!(text, priority, label)
    value = clock!(text, max_hours: 9999)
    return value if value.positive?

    raise Servora::RuleViolation, "Informe o prazo de #{label} da prioridade #{WorkOrder::PRIORITIES.fetch(priority).downcase}."
  end

  def clock!(text, end_of_day: false, max_hours: 23)
    match = TIME_FORMAT.match(text.to_s.strip)
    raise Servora::RuleViolation, "Use o formato HH:MM (recebido: #{text.presence || "vazio"})." unless match

    minutes = (match[1].to_i * 60) + match[2].to_i
    return minutes if end_of_day && minutes == 1440
    raise Servora::RuleViolation, "Horário inválido: #{text}." if match[2].to_i > 59 || match[1].to_i > max_hours

    minutes
  end
end
