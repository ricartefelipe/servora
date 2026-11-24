# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SLA settings" do
  let(:organization) { create(:organization) }
  let(:owner) { create(:membership, :owner, organization:) }

  def policies(overrides = {})
    WorkOrder::PRIORITIES.keys.index_with { { enabled: "0", business_hours_only: "1", warning_percent: "80" } }
      .merge(overrides)
  end

  def hours(weekdays = 1..5)
    (0..6).to_h do |weekday|
      fields = weekdays.include?(weekday) ? { start1: "08:00", end1: "12:00", start2: "13:00", end2: "18:00" } : {}
      [weekday.to_s, fields]
    end
  end

  it "saves targets per priority and the weekly business hours" do
    sign_in_as(owner)

    high = { enabled: "1", first_response: "02:00", resolution: "08:30", business_hours_only: "1", warning_percent: "75" }
    patch sla_settings_path, params: { sla: { policies: policies("high" => high), hours: } }

    expect(response).to redirect_to(sla_settings_path)
    policy = in_tenant(organization) { SlaPolicy.sole }
    expect(policy).to have_attributes(priority: "high", first_response_minutes: 120, resolution_minutes: 510, warning_percent: 75)
    expect(in_tenant(organization) { BusinessHour.count }).to eq(10)
    get sla_settings_path
    expect(response.body).to include('value="08:30"', 'value="13:00"')
  end

  it "explains invalid durations, times and overlapping intervals" do
    sign_in_as(owner)

    urgent = { enabled: "1", first_response: "1h", resolution: "04:00" }
    patch sla_settings_path, params: { sla: { policies: policies("urgent" => urgent), hours: } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Use o formato HH:MM (recebido: 1h).")

    overlapping = hours.merge("1" => { start1: "08:00", end1: "12:00", start2: "11:00", end2: "18:00" })
    patch sla_settings_path, params: { sla: { policies: policies, hours: overlapping } }
    expect(response.body).to include("não podem se sobrepor")
    expect(in_tenant(organization) { BusinessHour.count }).to eq(0)
  end

  it "adds and removes holidays" do
    sign_in_as(owner)

    post holidays_path, params: { holiday: { date: "2026-12-25", name: "Natal" } }
    holiday = in_tenant(organization) { Holiday.sole }
    post holidays_path, params: { holiday: { date: "2026-12-25", name: "Duplicado" } }
    follow_redirect!
    expect(response.body).to include("Natal", "Data já está em uso")

    delete holiday_path(holiday)
    expect(in_tenant(organization) { Holiday.count }).to eq(0)
  end

  it "is restricted to who manages the organization" do
    sign_in_as(create(:membership, :coordinator, organization:))

    get sla_settings_path

    expect(response).to have_http_status(:forbidden)
  end

  it "shows the deadlines on the work order" do
    scenario = build_work_order_scenario(organization:)
    configure_sla(organization)
    work_order = open_work_order(scenario)
    sign_in_as(scenario[:coordinator])

    get work_order_path(work_order)

    expect(response.body).to include("Prazos (SLA)", "Primeira resposta", "Resolução", "Vence")
  end
end
