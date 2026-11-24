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
