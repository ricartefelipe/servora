# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Field area" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:technician) { scenario[:technician] }
  let!(:work_order) { open_work_order(scenario, title: "Câmara fria sem refrigerar") }

  before { in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: technician).call } }

  def operation(kind, payload, version: nil, order: work_order)
    body = { operation: { id: SecureRandom.uuid, kind:, version:, work_order_id: order.id, payload: } }
    post field_operations_path, params: body, as: :json
  end

  it "lists the technician's visits and assigned orders" do
    sign_in_as(technician)

    get field_root_path

    expect(response.body).to include("Minha agenda", "Câmara fria sem refrigerar", "Atribuídas sem visita marcada")
  end

  it "shows the mobile execution view with offline-capable forms" do
    sign_in_as(technician)

    get field_work_order_path(work_order)

    expect(response.body).to include("Checklist", "Registro técnico", "Apontar horas", 'data-controller="field-sync"',
      'data-kind="technical_report"', 'data-controller="field-status"')
  end

  it "applies operations as JSON and revalidates access on every request" do
    sign_in_as(technician)

    operation("technical_report", { diagnosis: "Compressor travado", solution: "Substituição" })
    expect(response.parsed_body).to include("status" => "applied")

    other_order = open_work_order(scenario, title: "Não atribuída")
    operation("technical_report", { diagnosis: "x" }, order: other_order)
    expect(response).to have_http_status(:not_found)

    as_member(scenario[:coordinator]) { WorkOrders::Cancel.new(work_order:, actor: scenario[:coordinator], reason: "Duplicada").call }
    operation("technical_report", { diagnosis: "depois" })
    expect(response).to have_http_status(:forbidden)
  end

  describe "visit states" do
    let(:diego) { create_technician(organization, name: "Diego") }
    let!(:visit) { schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(11)) }

    def visit_operation(kind, payload = {}, id: SecureRandom.uuid)
      version = in_tenant(organization) { visit.reload.lock_version }
      body = { operation: { id:, kind:, version:, work_order_id: work_order.id, payload: payload.merge(visit_id: visit.id) } }
      post field_operations_path, params: body, as: :json
      response.parsed_body
    end

    it "offers the trip as the primary and the no-show, with a required reason, in the secondary sheet" do
      sign_in_as(diego)

      get field_work_order_path(work_order)

      page = response.parsed_body
      expect(page.at_css("form[data-kind='visit_travel'] button").text).to eq("Iniciar deslocamento")
      more = page.at_css("details summary[aria-label='Mais ações da visita']")
      expect(more.at_css("svg[aria-hidden=true]")).to be_present
      expect(more.text.strip).to be_empty
      expect(page.at_css("form[data-kind='visit_no_show'] textarea[required]")).to be_present
      expect(response.body).to include("Não foi possível atender", "Já está no local?")
    end

    it "moves the primary to the visit start and then to its completion" do
      sign_in_as(diego)
      in_tenant(organization) { Visits::Travel.new(visit: visit.reload, actor: diego).call }
      get field_work_order_path(work_order)
      expect(response.body).to include("Em deslocamento", "Iniciar atendimento", "Saída para o local às")
      expect(response.body).not_to include('data-kind="visit_travel"')

      in_tenant(organization) { Visits::Start.new(visit: visit.reload, actor: diego).call }
      get field_work_order_path(work_order)
      expect(response.body).to include("Concluir visita")
      expect(response.body).not_to include("Não foi possível atender")
    end

    it "lists a visit on the way in the technician's agenda as the highlighted one" do
      in_tenant(organization) do
        visit.reload.update_columns(scheduled_start: 1.hour.from_now, scheduled_end: 3.hours.from_now)
        Visits::Travel.new(visit: visit.reload, actor: diego).call
      end
      sign_in_as(diego)

      get field_root_path

      expect(response.parsed_body.at_css("#proxima-visita-titulo").text).to include("Em deslocamento")
    end

    def finish_visit_on_tuesday
      in_tenant(organization) do
        Visits::Start.new(visit: visit.reload, actor: diego, at: tuesday_at(9)).call
        Visits::Finish.new(visit: visit.reload, actor: diego, at: tuesday_at(10, 15)).call
      end
    end

    it "lists the visits finished today and counts them in the header when nothing else is left" do
      finish_visit_on_tuesday

      travel_to(tuesday_at(14)) do
        sign_in_as(diego)
        get field_root_path
      end

      page = response.parsed_body
      expect(page.at_css("header").text).to include("Hoje · 1 concluída")
      expect(page.at_css("#concluidas-hoje-titulo").text.squish).to eq("Concluídas hoje (1)")
      expect(page.at_css("[aria-labelledby='concluidas-hoje-titulo']").text).to include("10:15", work_order.number)
      expect(response.body).to include("Nenhuma visita pendente hoje.")
      expect(response.body).not_to include("Nenhuma visita hoje")
      expect(page.at_css("#proxima-visita-titulo")).to be_nil
    end

    it "keeps the upcoming count in the header while visits are left and still lists the finished ones" do
      finish_visit_on_tuesday
      later = open_work_order(scenario, title: "Segunda visita do dia")
      schedule(scenario, later, [diego], from: tuesday_at(15), to: tuesday_at(16))

      travel_to(tuesday_at(14)) do
        sign_in_as(diego)
        get field_root_path
      end

      page = response.parsed_body
      expect(page.at_css("header").text).to include("Hoje · 1 visita")
      expect(page.at_css("#proxima-visita-titulo")).to be_present
      expect(page.at_css("#concluidas-hoje-titulo").text.squish).to eq("Concluídas hoje (1)")
    end

    it "does not list visits finished on another day" do
      finish_visit_on_tuesday

      travel_to(tuesday_at(14) + 1.day) do
        sign_in_as(diego)
        get field_root_path
      end

      expect(response.body).not_to include("Concluídas hoje")
      expect(response.parsed_body.at_css("header").text).to include("Hoje · sem visitas")
    end

    it "applies the trip and the no-show sent by the allocated technician, once per operation id" do
      sign_in_as(diego)
      id = SecureRandom.uuid

      expect(visit_operation("visit_travel", { at: Time.current.iso8601 }, id:)).to include("status" => "applied")
      expect(visit_operation("visit_travel", { at: Time.current.iso8601 }, id:))
        .to include("status" => "applied", "result" => include("status" => "traveling"))
      expect(visit_operation("visit_no_show", { reason: "Cliente não atendeu no interfone" }))
        .to include("status" => "applied", "result" => include("status" => "no_show"))

      in_tenant(organization) do
        expect(visit.reload).to have_attributes(status: "no_show", cancel_reason: "Cliente não atendeu no interfone")
        expect(AuditEvent.where(auditable_id: work_order.id).pluck(:action)).to include("visit.travel_started", "visit.no_show")
        expect(FieldOperation.where(membership_id: diego.id).count).to eq(2)
      end
    end

    it "lets only the technician reserved on the visit change it" do
      sign_in_as(technician)

      outcome = visit_operation("visit_travel")

      expect(outcome).to include("status" => "rejected", "result" => include("error" => /técnico alocado/))
      expect(in_tenant(organization) { visit.reload.status }).to eq("scheduled")

      outsider = create_technician(organization, name: "Sem acesso")
      sign_in_as(outsider)
      visit_operation("visit_no_show", { reason: "Teste" })
      expect(response).to have_http_status(:not_found)
    end
  end

  it "refuses malformed operations" do
    sign_in_as(technician)

    body = { operation: { id: "não-é-uuid", kind: "checklist", work_order_id: work_order.id, payload: { a: 1 } } }
    post field_operations_path, params: body, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "keeps the field area to members who execute work orders" do
    sign_in_as(scenario[:coordinator])

    get field_root_path

    expect(response).to have_http_status(:forbidden)
  end

  it "serves a service worker that caches only static assets" do
    get pwa_service_worker_path(format: :js)

    expect(response.body).to include('url.pathname.startsWith("/assets/")', "/offline.html")
    expect(response.body).to include("fetch(request).catch(() => caches.match(OFFLINE_PAGE))")
  end
end
