# frozen_string_literal: true

module SlaHelpers
  # Mon–Fri 08:00–12:00 and 13:00–18:00 plus a policy for "high" priority.
  def configure_sla(organization, first_response: 120, resolution: 480, business_hours_only: true, warning_percent: 80)
    in_tenant(organization) do
      (1..5).each do |weekday|
        BusinessHour.create!(organization:, weekday:, start_minute: 480, end_minute: 720)
        BusinessHour.create!(organization:, weekday:, start_minute: 780, end_minute: 1080)
      end
      SlaPolicy.create!(organization:, priority: "high", first_response_minutes: first_response,
        resolution_minutes: resolution, business_hours_only:, warning_percent:)
    end
  end

  def clocks_of(work_order)
    in_tenant(work_order.organization_id) { SlaClock.where(work_order_id: work_order.id).index_by(&:metric) }
  end

  def move(scenario, work_order, to, reason: "Motivo informado")
    as_member(scenario[:coordinator]) do
      WorkOrders::Transition.new(work_order: work_order.reload, to:, actor: scenario[:coordinator], reason:).call
    end
  end
end

RSpec.configure do |config|
  config.include SlaHelpers
end
