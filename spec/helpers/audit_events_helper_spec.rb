# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditEventsHelper do
  def event(action, changeset, auditable_type: nil)
    AuditEvent.new(action:, changeset:, auditable_type:, actor_type: "user")
  end

  def lines(audit_event, references = Audit::ReferenceNames.new)
    AuditEventsHelper::Changeset.new(audit_event, references).entries.map do |entry|
      after = entry.after || "—"
      entry.pair ? "#{entry.label}: #{entry.before || "—"} → #{after}" : "#{entry.label}: #{after}"
    end
  end

  it "shows saved changes as before and after with the record's attribute names" do
    audit_event = event("organization.updated", {
      "id" => "0193a1b2-0000-7000-8000-000000000001", "travel_buffer_minutes" => [30, 45],
      "mfa_required_for_privileged" => [false, true], "legal_name" => [nil, "Clima Norte Ltda."],
      "updated_at" => %w[2026-11-23T10:00:00.000-03:00 2026-11-24T10:00:00.000-03:00]
    }, auditable_type: "Organization")

    expect(lines(audit_event)).to contain_exactly(
      "Deslocamento padrão: 30 min → 45 min",
      "Verificação em duas etapas obrigatória: Não → Sim",
      "Razão social: — → Clima Norte Ltda."
    )
  end

  it "hides credentials, digests and filtered values" do
    audit_event = event("payment_integration.updated", {
      "provider" => "asaas", "api_key" => "[ALTERADA]", "webhook_token_digest" => "[FILTRADO]"
    }, auditable_type: "PaymentIntegration")

    expect(lines(audit_event)).to contain_exactly("Provedor: asaas", "Chave de API: alterada")
    expect(helper.audit_changeset(audit_event)).to include("Valores sensíveis omitidos.")
  end

  it "keeps the replaced-credential marker through the redactor that stores events" do
    stored = Audit::Redactor.redact("provider" => "asaas", "api_key" => "[ALTERADA]", "webhook_token" => "segredo")
    audit_event = event("payment_integration.updated", stored, auditable_type: "PaymentIntegration")

    expect(stored).to include("api_key" => "[ALTERADA]", "webhook_token" => "[FILTRADO]")
    expect(lines(audit_event)).to contain_exactly("Provedor: asaas", "Chave de API: alterada")
  end

  it "does not list values that did not change" do
    unchanged = event("stock.minimum_changed", { "from" => 4, "to" => 4 })
    updated = event("organization.updated", { "travel_buffer_minutes" => [30, 30], "legal_name" => %w[A B] },
      auditable_type: "Organization")

    expect(lines(unchanged).first).to end_with("4 (sem alteração)")
    expect(lines(updated)).to contain_exactly("Razão social: A → B")
  end

  it "never shows from/to pairs of hidden or sensitive fields" do
    audit_event = event("equipment.relocated", {
      "from_widget_id" => "0193a1b2-0000-7000-8000-000000000001", "to_widget_id" => "0193a1b2-0000-7000-8000-000000000002",
      "from_api_key" => "[FILTRADO]", "to_api_key" => "[FILTRADO]"
    })

    expect(lines(audit_event)).to be_empty
    expect(helper.audit_changeset(audit_event)).not_to include("0193a1b2", "FILTRADO")
  end

  it "combines from/to into one line and translates statuses of the record type" do
    audit_event = event("contract.suspended", { "from" => "active", "to" => "suspended", "reason" => "Inadimplência" },
      auditable_type: "Contract")

    expect(lines(audit_event)).to contain_exactly("Situação: Vigente → Suspenso", "Motivo: Inadimplência")
  end

  it "localizes dates, quantities and money" do
    expect(lines(event("report.exported", { "report" => "ordens", "from" => "2026-11-01", "to" => "2026-11-24" })))
      .to contain_exactly("Período: 01/11/2026 → 24/11/2026", "Relatório: Ordens de serviço")
    expect(lines(event("stock.minimum_changed", { "warehouse" => "Central", "from" => "5.0", "to" => "7.5" })))
      .to contain_exactly("Estoque mínimo: 5 → 7,5", "Depósito: Central")
    expect(lines(event("receivable.discount_granted", { "amount" => "150.5", "reason" => nil })))
      .to contain_exactly("Valor: R$ 150,50", "Motivo: —")
  end

  it "shows referenced records by name and never their ids" do
    membership_id = "0193a1b2-0000-7000-8000-00000000000a"
    audit_event = event("work_order.assigned", { "membership_id" => membership_id, "visit_id" => SecureRandom.uuid })

    references = Audit::ReferenceNames.new(membership: { membership_id => "Bruno Lima" })

    expect(lines(audit_event, references)).to eq(["Técnico: Bruno Lima"])
    expect(lines(audit_event)).to eq(["Técnico: registro indisponível"])
  end

  it "shows only the new values of a creation" do
    audit_event = event("maintenance_plan.created", {
      "id" => [nil, SecureRandom.uuid], "title" => [nil, "Preventiva mensal"], "anchor_date" => [nil, "2026-11-27"],
      "active" => [nil, true]
    }, auditable_type: "MaintenancePlan")

    expect(lines(audit_event)).to contain_exactly("Título: Preventiva mensal", "Data base: 27/11/2026", "Ativo: Sim")
  end

  it "truncates long values and keeps the full text in the title" do
    long = "Cliente solicitou reagendamento por motivo de obra no prédio, com acesso restrito até a próxima semana."
    html = helper.audit_changeset(event("visit.rescheduled", { "note" => long }))

    expect(html).to include(%(title="#{long}"))
    expect(html).to include("…")
  end

  it "never raises on unknown record types or odd values" do
    audit_event = event("legacy.synced", { "weird-key" => { "nested" => [1, nil] }, "flag" => false },
      auditable_type: "NoSuchModel")

    expect(lines(audit_event)).to contain_exactly("Weird-key: Nested: 1, —", "Flag: Não")
  end
end
