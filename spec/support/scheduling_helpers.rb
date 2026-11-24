# frozen_string_literal: true

module SchedulingHelpers
  WEEKDAYS = (1..5)

  # Technician working Monday to Friday, 08:00–12:00 and 13:00–18:00.
  def create_technician(organization, name: "Técnico", skills: [])
    membership = create(:membership, :technician, organization:, user: create(:user, name:), hourly_cost: BigDecimal("60"))
    in_tenant(organization) do
      WEEKDAYS.each do |weekday|
        WorkSchedule.create!(organization:, membership:, weekday:, start_minute: 480, end_minute: 720)
        WorkSchedule.create!(organization:, membership:, weekday:, start_minute: 780, end_minute: 1080)
      end
      skills.each do |skill_name|
        skill = Skill.find_or_create_by!(organization:, name: skill_name)
        MembershipSkill.create!(organization:, membership:, skill:)
      end
      Membership.includes(:user, :work_schedules, :skills).find(membership.id)
    end
  end

  # A Tuesday in the organization's time zone.
  def tuesday_at(hour, minute = 0)
    Time.find_zone!("America/Sao_Paulo").parse(format("2026-12-01 %<hour>02d:%<minute>02d", hour:, minute:))
  end

  def schedule(scenario, work_order, technicians, from:, to:, travel: 0)
    as_member(scenario[:coordinator]) do
      Scheduling::ScheduleVisit.new(work_order: WorkOrder.includes(:organization).find(work_order.id), starts_at: from,
        ends_at: to, technicians:, actor: scenario[:coordinator], travel_minutes: travel).call
    end
  end
end

RSpec.configure do |config|
  config.include SchedulingHelpers
end
