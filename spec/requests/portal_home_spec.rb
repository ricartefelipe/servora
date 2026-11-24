# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer portal home" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }
  let(:approver) { create(:customer_contact, customer: scenario[:customer], portal_enabled: true, can_approve: true) }
  let(:follower) { create(:customer_contact, customer: scenario[:customer], portal_enabled: true, can_approve: false) }
  let(:neighbour) { build_work_order_scenario(organization:) }
  let(:foreign) { build_work_order_scenario }

  def at(text) = zone.parse(text)

  def quoting(data) = data.merge(author: data[:coordinator])

  # One open work order with a visit, an open charge and a sent quote.
  def seed(data, visit_at:, amount:)
    work_order = open_work_order(data)
    schedule(data, work_order, [create_technician(data[:organization])], from: visit_at, to: visit_at + 1.hour)
    add_authorized_item(data, work_order, unit_price: amount)
    issue_receivable(data, work_order, amount)
    send_quote(quoting(data), create_quote(quoting(data)))
    work_order
  end

  # Squished text of each summary cell, in order.
  def summary_cells
    response.parsed_body.css("section[aria-labelledby='resumo-title'] li").map { |cell| cell.text.squish }
  end

  def home_for(contact)
    enter_portal(contact)
    get portal_root_path
    expect(response).to have_http_status(:ok)
    summary_cells
  end

  before do
    late = travel_to(at("2026-11-20 10:00")) do
      open_work_order(scenario, title: "Cobrança vencida").tap do |work_order|
        add_authorized_item(scenario, work_order, unit_price: "200.00")
        issue_receivable(scenario, work_order, "200.00", due_on: Date.new(2026, 11, 21))
      end
    end
    travel_to(at("2026-11-30 08:00"))
    seed(scenario, visit_at: at("2026-12-01 09:00"), amount: "300.00")
    schedule(scenario, late, [create_technician(organization)], from: at("2026-12-02 14:00"), to: at("2026-12-02 15:00"))
    create_quote(quoting(scenario))
    seed(neighbour, visit_at: at("2026-12-01 08:00"), amount: "900.00")
    seed(foreign, visit_at: at("2026-11-30 10:00"), amount: "700.00")
  end

  it "summarizes visits, quotes, charges and work of the contact's own customer only", :aggregate_failures do
    expected = [
      "Visitas agendadas 2 Próxima em 01/12 às 09:00",
      "Orçamentos aguardando você 1 Analise e responda pelo portal",
      "Faturas em aberto 2 Saldo de R$ 500,00 1 vencida",
      "Atendimentos em andamento 2 Chamados e ordens de serviço abertos"
    ]
    expect(home_for(approver)).to eq(expected)
    cell_links = response.parsed_body.css("section[aria-labelledby='resumo-title'] li a").pluck("href")
    expect(cell_links).to eq([portal_visits_path, portal_quotes_path, portal_receivables_path, portal_work_orders_path])
    own_quote = in_tenant(organization) { Quote.find_by!(customer: scenario[:customer], status: "sent") }
    expect(response.body).to include("Orçamentos aguardando sua aprovação", own_quote.number, "R$ 450,00")
  end

  it "isolates the figures of another customer of the same organization and of another organization", :aggregate_failures do
    neighbour_contact = create(:customer_contact, customer: neighbour[:customer], portal_enabled: true, can_approve: true)
    foreign_contact = create(:customer_contact, customer: foreign[:customer], portal_enabled: true, can_approve: true)

    expected = [
      "Visitas agendadas 1 Próxima em 01/12 às 08:00",
      "Orçamentos aguardando você 1 Analise e responda pelo portal",
      "Faturas em aberto 1 Saldo de R$ 900,00",
      "Atendimentos em andamento 1 Chamados e ordens de serviço abertos"
    ]
    expect(home_for(neighbour_contact)).to eq(expected)
    expect(response.body).not_to include("vencida")

    expected = [
      "Visitas agendadas 1 Próxima em 30/11 às 10:00",
      "Orçamentos aguardando você 1 Analise e responda pelo portal",
      "Faturas em aberto 1 Saldo de R$ 700,00",
      "Atendimentos em andamento 1 Chamados e ordens de serviço abertos"
    ]
    expect(home_for(foreign_contact)).to eq(expected)
  end

  it "shows quotes awaiting the company's approvers to a contact who cannot approve", :aggregate_failures do
    cells = home_for(follower)

    expect(cells[1]).to eq("Orçamentos aguardando aprovação 1 A decisão cabe aos aprovadores da sua empresa")
    expect(response.body).not_to include("Orçamentos aguardando você", "Orçamentos aguardando sua aprovação")
    expect(response.body).to include("Somente os contatos autorizados pela sua empresa podem aprovar ou recusar orçamentos.")
  end

  it "keeps counting a visit while the technician is on the way" do
    visit = in_tenant(organization) { Visit.includes(allocations: :membership).find_by!(scheduled_start: at("2026-12-01 09:00")) }
    technician = visit.allocations.first.membership
    travel_to(at("2026-12-01 08:30"))
    as_member(technician) { Visits::Travel.new(visit:, actor: technician).call }

    expect(home_for(approver).first).to eq("Visitas agendadas 2 Equipe a caminho")
  end

  it "stops counting a quote once it is decided and a visit once it has ended", :aggregate_failures do
    quote = in_tenant(organization) { Quote.includes(:current_version).find_by!(customer: scenario[:customer], status: "sent") }
    enter_portal(approver)
    post decide_portal_quote_path(quote), params: { decision: { outcome: "approved", version_id: quote.current_version_id,
                                                                content_digest: quote.current_version.content_digest } }
    expect(in_tenant(organization) { quote.reload.status }).to eq("approved")
    travel_to(at("2026-12-01 11:00"))

    expected = [
      "Visitas agendadas 1 Próxima em 02/12 às 14:00",
      "Orçamentos aguardando você 0 Nenhum orçamento pendente"
    ]
    expect(home_for(approver).first(2)).to eq(expected)
    expect(response.body).to include("Nenhum orçamento pendente")
  end
end
