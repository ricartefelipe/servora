# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Indicador de sincronização e situação da visita no campo", :js do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:diego) { create_technician(organization, name: "Diego") }
  let!(:work_order) { open_work_order(scenario, title: "Split com ruído") }
  let!(:trip_visit) { schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(11)) }

  # What the device reports (navigator.onLine and the online/offline events).
  def device(online:)
    page.execute_script(<<~JS, online)
      window.servoraDeviceOnline = arguments[0]
      Object.defineProperty(navigator, "onLine", { configurable: true, get: () => window.servoraDeviceOnline })
      window.dispatchEvent(new Event(arguments[0] ? "online" : "offline"))
    JS
  end

  # Whether the operations endpoint answers; while unavailable every request
  # gets a 503 and the operation stays queued on the device.
  def server(available:)
    if available
      allow_any_instance_of(Field::OperationsController).to receive(:create).and_call_original # rubocop:disable RSpec/AnyInstance
    else
      allow_any_instance_of(Field::OperationsController).to receive(:create) do |controller| # rubocop:disable RSpec/AnyInstance
        controller.send(:skip_authorization)
        controller.head(:service_unavailable)
      end
    end
  end

  def chip = find("[data-controller~='field-status']")

  it "mostra sincronizado, offline com pendências e a falha com nova tentativa" do
    sign_in_as(diego)
    visit field_work_order_path(work_order)
    expect(chip).to have_css("[role='status'][aria-live='polite']", text: "Sincronizado")
    expect(chip).to have_no_button("Tentar")

    server(available: false)
    device(online: false)
    expect(chip).to have_text("Offline")
    fill_in "Diagnóstico", with: "Rolamento desgastado"
    click_on "Salvar registro"
    expect(chip).to have_text("Offline · 1 pendente")
    expect(page).to have_text("1 registro aguardando envio.")

    # Back online, but the server does not answer: the queue is kept.
    device(online: true)
    expect(chip).to have_text("Falha ao sincronizar")
    expect(page).to have_text("O servidor não respondeu.")
    expect(in_tenant(organization) { work_order.reload.diagnosis }).to be_nil

    server(available: true)
    within(chip) { click_on "Tentar" }
    expect(chip).to have_text("Sincronizado")
    expect(chip).to have_no_button("Tentar")
    expect(page).to have_text("Sincronizado com sucesso.")
    expect(page).to have_no_text("aguardando envio")
    expect(in_tenant(organization) { work_order.reload.diagnosis }).to eq("Rolamento desgastado")
  end

  it "lê a fila também na agenda e a envia quando a conexão volta" do
    sign_in_as(diego)
    visit field_work_order_path(work_order)
    server(available: false)
    device(online: false)
    fill_in "Solução aplicada", with: "Troca do rolamento"
    click_on "Salvar registro"
    expect(chip).to have_text("Offline · 1 pendente")

    server(available: true)
    page.execute_script("Turbo.visit(arguments[0])", field_root_path)
    expect(page).to have_text("Minha agenda")
    expect(page).to have_no_css("[data-controller~='field-sync']")
    expect(chip).to have_text("Offline · 1 pendente")
    expect(in_tenant(organization) { work_order.reload.solution }).to be_nil

    device(online: true)
    expect(chip).to have_text("Sincronizado")
    expect(in_tenant(organization) { work_order.reload.solution }).to eq("Troca do rolamento")
  end

  it "inicia o deslocamento sem conexão e segue para o atendimento quando sincroniza" do
    sign_in_as(diego)
    visit field_work_order_path(work_order)

    server(available: false)
    device(online: false)
    click_on "Iniciar deslocamento"
    expect(page).to have_button("Iniciar deslocamento", disabled: true)
    expect(page).to have_text("Deslocamento registrado neste aparelho.")
    expect(chip).to have_text("Offline · 1 pendente")
    expect(in_tenant(organization) { trip_visit.reload.status }).to eq("scheduled")

    server(available: true)
    device(online: true)
    expect(page).to have_button("Iniciar atendimento")
    expect(page).to have_text("Deslocamento iniciado.")
    expect(page).to have_css(".sv-badge", text: "Em deslocamento")
    expect(chip).to have_text("Sincronizado")
    expect(in_tenant(organization) { trip_visit.reload.status }).to eq("traveling")
  end

  it "registra pelo menu secundário que não foi possível atender, com motivo obrigatório" do
    sign_in_as(diego)
    visit field_work_order_path(work_order)

    find("summary[aria-label='Mais ações da visita']").click
    find("summary", text: "Não foi possível atender").click
    click_on "Registrar cliente ausente"
    expect(in_tenant(organization) { trip_visit.reload.status }).to eq("scheduled")

    fill_in "Motivo", with: "Portaria sem autorização de entrada"
    click_on "Registrar cliente ausente"

    expect(page).to have_text("Visita registrada como não atendida: cliente ausente.")
    expect(page).to have_no_button("Iniciar deslocamento")
    in_tenant(organization) do
      expect(trip_visit.reload).to have_attributes(status: "no_show", cancel_reason: "Portaria sem autorização de entrada")
      expect(work_order.reload.status).to eq("waiting_customer")
    end
  end

  it "encadeia as versões das ações de visita gravadas em sequência sem conexão" do
    sign_in_as(diego)
    visit field_work_order_path(work_order)

    chained = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("controllers/field_queue").then(({ chainVisitVersions }) => {
        const travel = { id: "a", kind: "visit_travel", version: 3, payload: { visit_id: "v1" } }
        const queue = [
          { id: "b", kind: "visit_no_show", version: 3, payload: { visit_id: "v1" } },
          { id: "c", kind: "visit_no_show", version: 3, payload: { visit_id: "v2" } },
          { id: "d", kind: "checklist", version: 3, payload: { visit_id: "v1" } }
        ]
        const applied = chainVisitVersions(queue, travel, { status: "applied", result: { version: 4 } })
        const conflict = chainVisitVersions(queue, travel, { status: "conflict", result: { version: 9 } })
        done({ applied: applied.map((op) => op.version), conflict: conflict.map((op) => op.version) })
      })
    JS

    expect(chained).to eq("applied" => [4, 3, 3], "conflict" => [3, 3, 3])
  end
end
