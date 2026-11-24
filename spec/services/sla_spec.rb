# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sla do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }

  before { configure_sla(organization) }

  def at(text) = zone.parse(text)

  it "starts both clocks in business time from the request" do
    work_order = travel_to(at("2026-11-24 17:00")) { open_work_order(scenario) }

    clocks = clocks_of(work_order)
    expect(clocks["first_response"]).to have_attributes(status: "running", due_at: at("2026-11-25 09:00"),
      warn_at: at("2026-11-25 08:36"))
    # 17:00–18:00 (1 h) + 08:00–12:00 (4 h) + 13:00–16:00 (3 h)
    expect(clocks["resolution"].due_at).to eq(at("2026-11-25 16:00"))
    expect(in_tenant(organization) { SlaClockEvent.where(kind: "started").count }).to eq(2)
  end

  it "meets the first response when the order is scheduled or started" do
    work_order = travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }

    travel_to(at("2026-11-24 10:30")) { move(scenario, work_order, "in_progress") }

    expect(clocks_of(work_order)["first_response"]).to have_attributes(status: "met", consumed_seconds: 5400)
  end

  it "pauses resolution while waiting for parts and resumes with the remaining time" do
    work_order = travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }
    travel_to(at("2026-11-24 10:00")) { move(scenario, work_order, "in_progress") }
    travel_to(at("2026-11-24 11:00")) { move(scenario, work_order, "waiting_parts") }

    paused = clocks_of(work_order)["resolution"]
    expect(paused).to have_attributes(status: "paused", consumed_seconds: 7200, due_at: nil)

    travel_to(at("2026-11-26 14:00")) { move(scenario, work_order, "in_progress") }
    # 6 h remaining: Thursday 14:00–18:00 and Friday 08:00–10:00
    expect(clocks_of(work_order)["resolution"]).to have_attributes(status: "running", due_at: at("2026-11-27 10:00"))
  end

  it "records breached deadlines on completion and resumes on reopening" do
    work_order = travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }
    ready_to_complete!(scenario, work_order)
    travel_to(at("2026-11-25 17:00")) do
      as_member(scenario[:coordinator]) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }
    end

    resolution = clocks_of(work_order)["resolution"]
    expect(resolution).to have_attributes(status: "breached", breached_at: at("2026-11-24 18:00"))

    travel_to(at("2026-11-26 09:00")) do
      as_member(scenario[:coordinator]) do
        WorkOrders::Reopen.new(work_order: work_order.reload, actor: scenario[:coordinator], reason: "Voltou a falhar").call
      end
    end
    expect(clocks_of(work_order)["resolution"]).to have_attributes(status: "running", segment: 2, due_at: at("2026-11-26 09:00"))
  end

  it "cancels running clocks with the order and ignores priorities without policy" do
    work_order = travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }
    as_member(scenario[:coordinator]) { WorkOrders::Cancel.new(work_order:, actor: scenario[:coordinator], reason: "Duplicada").call }

    expect(clocks_of(work_order).values.map(&:status)).to all(eq("canceled"))
    expect(clocks_of(open_work_order(scenario, priority: "low"))).to be_empty
  end

  it "counts continuously when the policy ignores business hours" do
    in_tenant(organization) { SlaPolicy.find_by!(priority: "high").update!(business_hours_only: false) }

    work_order = travel_to(at("2026-11-28 22:00")) { open_work_order(scenario) }

    expect(clocks_of(work_order)["first_response"].due_at).to eq(at("2026-11-29 00:00"))
  end

  it "summarizes breached and at-risk deadlines on the dashboard" do
    travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }

    overview = ->(membership, now) { in_tenant(organization) { Dashboards::Overview.new(membership:).sla_alerts(now:) } }

    expect(overview.call(scenario[:coordinator], at("2026-11-24 10:40"))).to eq(breached: 0, at_risk: 1)
    expect(overview.call(scenario[:coordinator], at("2026-11-25 09:00"))).to eq(breached: 2, at_risk: 0)
    expect(overview.call(scenario[:technician], at("2026-11-25 09:00"))).to be_nil
  end

  describe Sla::Scan do
    include ActiveJob::TestHelper

    # Past dates: the outbox dispatcher compares availability with the database clock.
    it "alerts once per clock for warnings and breaches, even when scanned repeatedly" do
      work_order = travel_to(at("2026-11-17 09:00")) { open_work_order(scenario) }
      in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call }

      results = travel_to(at("2026-11-17 10:40")) { Array.new(2) { in_tenant(organization) { described_class.new.call } } }
      expect(results).to eq([{ warned: 1, breached: 0 }, { warned: 0, breached: 0 }])

      travel_to(at("2026-11-17 11:05")) { in_tenant(organization) { described_class.new.call } }
      run_dispatcher

      notifications = in_tenant(organization) { Notification.order(:created_at).pluck(:kind, :recipient_membership_id) }
      expect(notifications.map(&:first).tally).to eq("sla.warning" => 2, "sla.breached" => 2)
      expect(notifications.map(&:last).uniq).to contain_exactly(scenario[:coordinator].id, scenario[:technician].id)
      expect(clocks_of(work_order)["first_response"].breached_at).to eq(at("2026-11-17 11:05"))
    end

    it "runs for every active organization through the job" do
      travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }

      travel_to(at("2026-11-25 09:00")) { Sla::ScanJob.perform_now }

      expect(in_tenant(organization) { SlaClock.where.not(breach_notified_at: nil).count }).to eq(2)
    end
  end
end
