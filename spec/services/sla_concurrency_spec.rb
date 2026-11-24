# frozen_string_literal: true

require "rails_helper"

# Two scans (overlapping job runs) see the same overdue clocks. The
# conditional claim on the clock row lets only one of them publish the alert.
RSpec.describe Sla, :committed do # concurrent alert scans
  it "publishes each breach alert once" do
    scenario = build_work_order_scenario
    organization = scenario[:organization]
    configure_sla(organization)
    zone = ActiveSupport::TimeZone[organization.time_zone]
    travel_to(zone.parse("2026-11-17 09:00")) { open_work_order(scenario) }
    later = zone.parse("2026-11-18 09:00")

    results = ConcurrencyHelpers.run_in_parallel(3) { in_tenant(organization) { Sla::Scan.new(now: later).call[:breached] } }

    expect(results.sum).to eq(2)
    expect(in_tenant(organization) { OutboxEvent.where(event_type: "sla.breached").count }).to eq(2)
    expect(in_tenant(organization) { SlaClockEvent.where(kind: "breached").count }).to eq(2)
  end
end
