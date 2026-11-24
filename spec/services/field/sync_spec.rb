# frozen_string_literal: true

require "rails_helper"

RSpec.describe Field::Sync do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:technician) { scenario[:technician] }
  let!(:work_order) { open_work_order(scenario) }

  def sync(kind, payload, version: nil, id: SecureRandom.uuid, membership: technician, order: work_order)
    operation = described_class::Operation.new(id:, kind:, version:, payload:)
    in_tenant(organization) { described_class.new(work_order: order.reload, membership:, operation:).call }
  end

  it "applies a queued time entry once, however many times it is resent" do
    id = SecureRandom.uuid
    payload = { "started_at" => "2026-11-24T12:00:00Z", "ended_at" => "2026-11-24T13:30:00Z", "notes" => "Sem sinal no local" }

    first = sync("time_entry", payload, id:)
    second = sync("time_entry", payload, id:)

    expect(first).to eq(second)
    expect(first).to include("status" => "applied", "result" => include("minutes" => 90))
    expect(in_tenant(organization) { [TimeEntry.where(source: "offline").count, FieldOperation.count] }).to eq([1, 1])
  end

  it "never overwrites a technical report changed after the draft was written" do
    seen_version = in_tenant(organization) { work_order.reload.lock_version }
    in_tenant(organization) { work_order.reload.update!(diagnosis: "Diagnóstico do escritório") }

    outcome = sync("technical_report", { "diagnosis" => "Diagnóstico de campo", "solution" => "Troca" }, version: seen_version)

    expect(outcome).to include("status" => "conflict", "result" => include("diagnosis" => "Diagnóstico do escritório"))
    expect(in_tenant(organization) { work_order.reload.diagnosis }).to eq("Diagnóstico do escritório")
    applied = sync("technical_report", { "diagnosis" => "Revisado em campo", "solution" => "Troca" },
      version: outcome.dig("result", "version"))
    expect(applied["status"]).to eq("applied")
  end

  it "detects checklist conflicts by item version" do
    item = in_tenant(organization) { work_order.checklist_items.find_by!(response_kind: "check") }
    version = item.lock_version
    in_tenant(organization) { item.reload.update!(response: "nao") }

    outcome = sync("checklist", { "item_id" => item.id, "response" => "sim" }, version:)

    expect(outcome).to include("status" => "conflict", "result" => include("response" => "nao"))
  end

  describe "visit operations" do
    let(:technician) { create_technician(organization, name: "Diego") }
    let!(:visit) { schedule(scenario, work_order, [technician], from: tuesday_at(9), to: tuesday_at(11)) }

    def visit_version = in_tenant(organization) { visit.reload.lock_version }

    it "records the trip once with the device time, however many times it is resent" do
      id = SecureRandom.uuid
      version = visit_version
      travel(15.minutes) do
        tapped_at = 10.minutes.ago.change(usec: 0)
        payload = { "visit_id" => visit.id, "at" => tapped_at.iso8601 }

        first = sync("visit_travel", payload, id:, version:)
        second = sync("visit_travel", payload, id:, version:)

        expect(first).to eq(second)
        expect(first).to include("status" => "applied",
          "result" => include("status" => "traveling", "status_label" => "Em deslocamento"))
        expect(in_tenant(organization) { visit.reload }).to have_attributes(status: "traveling", travel_started_at: tapped_at)
      end
      transitions = in_tenant(organization) { VisitTransition.where(visit_id: visit.id, to_status: "traveling").count }
      expect([transitions, in_tenant(organization) { FieldOperation.count }]).to eq([1, 1])
    end

    it "returns the server state when the visit changed after the screen was loaded" do
      seen = visit_version
      in_tenant(organization) { Visits::Travel.new(visit: visit.reload, actor: technician).call }

      outcome = sync("visit_no_show", { "visit_id" => visit.id, "reason" => "Portão fechado" }, version: seen)

      expect(outcome).to include("status" => "conflict", "result" => include("status" => "traveling", "version" => visit_version))
      applied = sync("visit_no_show", { "visit_id" => visit.id, "reason" => "Portão fechado" },
        version: outcome.dig("result", "version"))
      expect(applied).to include("status" => "applied", "result" => include("status" => "no_show"))
      expect(in_tenant(organization) { work_order.reload.status }).to eq("waiting_customer")
    end

    it "requires the reason of a no-show" do
      outcome = sync("visit_no_show", { "visit_id" => visit.id, "reason" => " " }, version: visit_version)

      expect(outcome).to include("status" => "rejected", "result" => { "error" => "Informe o motivo." })
      expect(in_tenant(organization) { visit.reload.status }).to eq("scheduled")
    end

    it "accepts visit changes only from a technician reserved on that visit" do
      assigned_elsewhere = scenario[:technician]
      in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: assigned_elsewhere).call }

      outcome = sync("visit_travel", { "visit_id" => visit.id }, membership: assigned_elsewhere)

      expect(outcome).to include("status" => "rejected", "result" => include("error" => /técnico alocado/))
      expect(sync("visit_travel", { "visit_id" => visit.id }, membership: scenario[:coordinator])["status"]).to eq("rejected")
      expect(in_tenant(organization) { visit.reload.status }).to eq("scheduled")
    end

    it "refuses a visit of another work order and invalid moves" do
      other = open_work_order(scenario, title: "Outra")

      expect(sync("visit_travel", { "visit_id" => visit.id }, order: other)["status"]).to eq("rejected")
      sync("visit_travel", { "visit_id" => visit.id }, version: visit_version)
      expect(sync("visit_travel", { "visit_id" => visit.id }, version: visit_version)).to include("status" => "rejected",
        "result" => include("error" => /em deslocamento/))
    end

    it "rejects visit changes that do not carry the version they were based on" do
      outcome = sync("visit_travel", { "visit_id" => visit.id })

      expect(outcome).to include("status" => "rejected", "result" => include("error" => /Versão da visita ausente/))
      expect(in_tenant(organization) { visit.reload.status }).to eq("scheduled")
    end
  end

  it "rejects invalid data and operations of another member with the same id" do
    id = SecureRandom.uuid
    rejected = sync("time_entry", { "started_at" => "2026-11-24T13:00:00Z", "ended_at" => "2026-11-24T12:00:00Z" }, id:)
    expect(rejected).to include("status" => "rejected")

    other = create(:membership, :technician, organization:)
    expect(sync("time_entry", {}, id:,
      membership: other)).to include("status" => "rejected", "result" => { "error" => "Operação inválida." })
    expect(sync("unknown", {})).to include("status" => "rejected")
  end
end
