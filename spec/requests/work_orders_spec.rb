# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Work orders" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }

  it "opens a work order from the form" do
    sign_in_as(scenario[:coordinator])

    post work_orders_path, params: { work_order: { service_location_id: scenario[:location].id, title: "Vazamento",
                                                   problem_description: "Água pingando", origin: "whatsapp", priority: "urgent",
                                                   service_type_id: scenario[:service_type].id,
                                                   equipment_ids: [scenario[:equipment].id] } }

    work_order = in_tenant(organization) { WorkOrder.sole }
    expect(response).to redirect_to(work_order_path(work_order))
    follow_redirect!
    expect(response.body).to include("Vazamento", "Urgente", "Medir pressão de sucção")
  end

  it "counts the open states in the strip, starting with the orders still open" do
    fresh = open_work_order(scenario, title: "Recém-aberta")
    waiting = open_work_order(scenario, title: "Sem peça")
    in_tenant(organization) do
      fresh.update_columns(status: "open")
      waiting.update_columns(status: "waiting_parts")
    end
    sign_in_as(scenario[:coordinator])

    get work_orders_path

    tiles = response.parsed_body.css("nav[aria-label='Ordens em aberto por situação'] a")
    expect(tiles.map { |tile| tile.text.squish }).to eq(["Aberta 1", "Aprovada 0", "Agendada 0", "Em execução 0",
                                                         "Aguardando peças 1", "Aguardando cliente 0", "Reaberta 0"])
    expect(tiles.first["href"]).to eq(work_orders_path(situacao: "open"))
    expect(tiles[4].at_css("svg.text-amber-600")).to be_present
  end

  describe "deadline filter" do
    let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }
    # At 10:40 on Tuesday: the order opened on Monday is past both deadlines,
    # the one opened at 09:00 has its first response at risk (warning from 10:36)
    # and the low-priority one has no deadline (no SLA policy).
    let(:overdue) { travel_to(at("2026-11-23 09:00")) { open_work_order(scenario, title: "Atrasada") } }
    let(:at_risk) { travel_to(at("2026-11-24 09:00")) { open_work_order(scenario, title: "Em risco") } }
    let(:on_time) { travel_to(at("2026-11-24 09:00")) { open_work_order(scenario, title: "Sem prazo", priority: "low") } }

    # Clocks start when the order is opened, so the policy comes first.
    before do
      configure_sla(organization)
      [overdue, at_risk, on_time]
    end

    def at(text) = zone.parse(text)

    def list(membership, **params)
      travel_to(at("2026-11-24 10:40")) do
        sign_in_as(membership)
        get work_orders_path(**params)
      end
      response.parsed_body
    end

    def titles(page) = page.css("table tbody tr td a.sv-link").map(&:text)

    def row_badges(page, work_order)
      row = page.at_css("table tbody tr:has(a[href='#{work_order_path(work_order)}'])")
      row.css(".sv-badge").map { |node| node.text.squish }
    end

    it "lists only the orders with a deadline past or at risk" do
      expect(titles(list(scenario[:coordinator], prazo: "estourado"))).to eq(["Atrasada"])

      page = list(scenario[:coordinator], prazo: "em_risco")
      expect(titles(page)).to eq(["Em risco"])
      expect(row_badges(page, at_risk)).to include("Prazo em risco")
      expect(page.at_css("select[name=prazo] option[selected]")["value"]).to eq("em_risco")
      expect(page.at_css("caption").text).to include("Prazo em risco")
    end

    it "marks the deadline in each row of the full list, danger with an icon when past" do
      page = list(scenario[:coordinator])

      expect(titles(page)).to contain_exactly("Atrasada", "Em risco", "Sem prazo")
      expect(row_badges(page, on_time)).not_to include("Prazo estourado", "Prazo em risco")
      row = page.at_css("table tbody tr:has(a[href='#{work_order_path(overdue)}'])")
      badge = row.at_css(".sv-badge:contains('Prazo estourado')")
      expect(badge["class"]).to include("bg-rose-50")
      expect(badge.at_css("svg")).to be_present
    end

    it "marks the deadline under the title in the phone list too" do
      page = list(scenario[:coordinator], prazo: "estourado")

      item = page.at_css("ul[aria-label='Ordens de serviço'] > li")
      expect(item.css("p").last.css(".sv-badge").map { |node| node.text.squish }).to include("Alta", "Prazo estourado")
    end

    it "lays a phone row out as number, title, customer and location, then badges with the request date" do
      page = list(scenario[:coordinator], prazo: "estourado")

      lines = page.css("ul[aria-label='Ordens de serviço'] > li > a > p")
      customer = in_tenant(organization) { scenario[:customer].reload.display_name }
      expect(lines[0].text.squish).to eq(overdue.number)
      expect(lines[0]["class"].split).to include("whitespace-nowrap")
      expect(lines[1].text.squish).to eq("Atrasada")
      expect(lines[2].text.squish).to eq("#{customer} · #{scenario[:location].name}")
      expect(lines[3].text.squish).to end_with("Solicitada em 23/11/2026 09:00")
    end

    it "offers short deadline options in a select wide enough to show them" do
      page = list(scenario[:coordinator])

      select = page.at_css("select[name=prazo]")
      expect(select.css("option").map(&:text)).to eq(["Todos", "Estourado", "Em risco"])
      expect(select.parent["class"].split).to include("sm:w-40")
    end

    it "names the filter of an empty list and offers to clear it" do
      page = list(scenario[:coordinator], prazo: "estourado", situacao: "scheduled")

      expect(page.at_css("table")).to be_nil
      expect(page.text).to include("Nenhuma ordem neste filtro", "Filtro aplicado: Situação: Agendada · Prazo estourado.")
      expect(page.at_css("a.sv-btn-secondary:contains('Limpar filtro')")["href"]).to eq(work_orders_path)
    end

    it "searches with blanks collapsed and names the search exactly as it was run" do
      expect(titles(list(scenario[:coordinator], q: "  em    risco "))).to eq(["Em risco"])

      long_term = "#{"inexistente " * 8}caudafinal"
      page = list(scenario[:coordinator], q: long_term)

      searched = WorkOrders::SearchQuery.normalize_term(long_term)
      expect(page.text).to include("Filtro aplicado: Busca: “#{searched}”.")
      expect(page.text).not_to include("caudafinal")
    end

    it "ignores an unknown value and keeps the policy scope" do
      expect(titles(list(scenario[:coordinator], prazo: "qualquer"))).to contain_exactly("Atrasada", "Em risco", "Sem prazo")

      in_tenant(organization) { WorkOrders::Assign.new(work_order: at_risk, membership: scenario[:technician]).call }
      page = list(scenario[:technician], prazo: "estourado")
      expect(page.css("ul[aria-label='Ordens de serviço'] > li")).to be_empty
      expect(titles(list(scenario[:technician], prazo: "em_risco"))).to eq(["Em risco"])
    end
  end

  describe "order actions" do
    let(:work_order) { open_work_order(scenario) }

    def show_page
      sign_in_as(scenario[:coordinator])
      get work_order_path(work_order)
      response.parsed_body
    end

    it "makes the target state an explicit, required choice" do
      select = show_page.at_css("section[aria-label='Ações da ordem'] select[name='status_change[to]']")

      expect(select["required"]).to be_present
      expect(select.css("option").first.then { |option| [option.text, option["value"]] }).to eq(["Selecione a situação", ""])
      expect(select.at_css("option[selected]")).to be_nil
    end

    it "offers reopening in the header of a completed order instead of an empty action card" do
      ready_to_complete!(scenario, work_order)
      in_tenant(organization) { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }

      page = show_page

      expect(page.at_css("section[aria-label='Ações da ordem']")).to be_nil
      reopen = page.at_css("main header details summary:contains('Reabrir')")
      expect(reopen).to be_present
      expect(reopen.parent.at_css("form[action='#{reopen_work_order_path(work_order)}'] textarea[required]")).to be_present
    end

    it "shows no action card on a canceled order" do
      in_tenant(organization) { WorkOrders::Cancel.new(work_order:, actor: scenario[:coordinator], reason: "Duplicada").call }

      page = show_page

      expect(page.at_css("section[aria-label='Ações da ordem']")).to be_nil
      expect(page.at_css("main header details")).to be_nil
    end
  end

  it "completes a work order with assigned technicians and records them in the report" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call }
    ready_to_complete!(scenario, work_order)
    sign_in_as(scenario[:coordinator])

    post complete_work_order_path(work_order)

    report = in_tenant(organization) { WorkOrderReport.sole }
    expect(report.data["technicians"]).to eq([scenario[:technician].user.name])
  end

  it "shows why completion is refused" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Transition.new(work_order:, to: "in_progress", actor: nil).call }
    sign_in_as(scenario[:coordinator])

    post complete_work_order_path(work_order)
    follow_redirect!

    expect(response.body).to include("Para concluir", "Registrar o diagnóstico")
  end

  it "lets the assigned technician fill the checklist and the technical report" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: scenario[:technician]).call }
    item = in_tenant(organization) { work_order.checklist_items.find_by!(response_kind: "check") }
    sign_in_as(scenario[:technician])

    patch work_order_checklist_item_path(work_order, item),
      params: { answer: { response: "sim", lock_version: item.lock_version } }
    patch update_report_work_order_path(work_order), params: { report: { diagnosis: "Filtro sujo", solution: "Limpeza",
                                                                         lock_version: 1 } }

    in_tenant(organization) do
      expect(item.reload.response).to eq("sim")
      expect(work_order.reload.diagnosis).to eq("Filtro sujo")
    end
    post complete_work_order_path(work_order)
    expect(response).to have_http_status(:forbidden)
  end

  it "hides unassigned work orders from technicians" do
    work_order = open_work_order(scenario)
    sign_in_as(scenario[:technician])

    get work_orders_path
    expect(response.body).not_to include(work_order.number)
    get work_order_path(work_order)
    expect(response).to have_http_status(:not_found)
  end

  it "converts an approved quote idempotently through the endpoint" do
    quote_scenario = build_quote_scenario(organization:)
    quote = create_quote(quote_scenario)
    version = send_quote(quote_scenario, quote)
    in_tenant(organization) do
      Quotes::Decide.new(quote: quote.reload, version_id: version.id, decision: "approved", digest: version.content_digest,
        contact: quote_scenario[:approver], channel: "portal").call
    end
    sign_in_as(scenario[:coordinator])

    2.times { post convert_quote_path(quote) }

    expect(in_tenant(organization) { WorkOrder.where(quote_version_id: version.id).count }).to eq(1)
    expect(flash[:notice]).to eq("Este orçamento já foi convertido.")
  end

  it "manages service types with checklist" do
    sign_in_as(scenario[:coordinator])

    post service_types_path, params: { service_type: { name: "Instalação", active: "1",
                                                       checklist_items_attributes: { "0" => { label: "Teste de estanqueidade",
                                                                                              response_kind: "check",
                                                                                              required: "1", position: "1" } } } }

    expect(in_tenant(organization) { ServiceType.find_by!(name: "Instalação").checklist_items.map(&:label) })
      .to eq(["Teste de estanqueidade"])
  end
end
