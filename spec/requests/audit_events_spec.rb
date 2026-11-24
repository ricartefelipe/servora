# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audit trail" do
  let(:organization) { create(:organization) }
  let(:auditor) { create(:membership, :auditor, organization:) }
  let(:technician) { create(:membership, :technician, organization:) }

  def table = response.body[%r{<table.*</table>}m].to_s

  def record(action, changes = {}, auditable: nil)
    as_member(auditor) { AuditEvent.record!(action:, auditable:, changes:) }
  end

  before do
    record("work_order.assigned", { membership_id: technician.id, visit_id: SecureRandom.uuid })
    record("organization.updated", {
      "id" => [nil, organization.id], "organization_id" => organization.id, "travel_buffer_minutes" => [30, 45],
      "webhook_token_digest" => %w[resumo-anterior resumo-novo], "updated_at" => [1.day.ago, Time.current]
    }, auditable: organization)
    record("legacy_module.synced", { note: "Importado da versão anterior" })
  end

  it "shows readable labels and changes, with the raw key for auditors" do
    sign_in_as(auditor)

    get audit_events_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ordem de serviço · técnico atribuído", "work_order.assigned")
    expect(response.body).to include("Organização · configurações alteradas", "Deslocamento padrão", "45 min")
    expect(response.body).to include("Técnico:", technician.user.name)
    expect(response.body).to include("Legacy module · synced", "Importado da versão anterior")
    expect(response.body).to include("Valores sensíveis omitidos.")
  end

  it "hides ids, digests and technical fields" do
    sign_in_as(auditor)

    get audit_events_path

    expect(table).to include("Deslocamento padrão")
    expect(table).not_to include(technician.id, organization.id)
    expect(table).not_to include("webhook_token_digest", "resumo-anterior", "[FILTRADO]")
    expect(table).not_to include("organization_id", "updated_at", "visit_id")
  end

  it "keeps the action filter, offering labelled options grouped by area" do
    sign_in_as(auditor)

    get audit_events_path, params: { acao: "work_order.assigned" }

    expect(response.body).to include(%(<optgroup label="Ordem de serviço">))
    expect(response.body)
      .to include(%(<option selected="selected" value="work_order.assigned">Ordem de serviço · técnico atribuído</option>))
    expect(table).to include("work_order.assigned")
    expect(table).not_to include("Deslocamento padrão")
  end

  it "stays forbidden for operational roles" do
    sign_in_as(technician)

    get audit_events_path

    expect(response).to have_http_status(:forbidden)
  end
end
