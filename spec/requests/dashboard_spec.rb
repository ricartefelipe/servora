# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:zone) { ActiveSupport::TimeZone[organization.time_zone] }

  def at(text) = zone.parse(text)

  def member(role, name:)
    create(:membership, role, organization:, user: create(:user, name:))
  end

  # A work order for its own customer, so each visit can be told apart on the page.
  def order_for(customer_name)
    customer = create(:customer, organization:, name: customer_name)
    location = create(:service_location, customer:, city: "Campinas")
    as_member(scenario[:coordinator]) do
      WorkOrders::Create.new(organization:, actor: scenario[:coordinator], attributes: {
        title: "Manutenção #{customer_name}", problem_description: "Revisão periódica.", origin: "phone", priority: "normal",
        customer_id: customer.id, service_location_id: location.id, service_type_id: scenario[:service_type].id
      }).call
    end
  end

  it "opens with the ruby cover, the greeting and what needs attention for a coordinator" do
    coordinator = member(:coordinator, name: "Bruno Coordenador")
    configure_sla(organization)
    travel_to(at("2026-11-24 09:00")) { open_work_order(scenario) }

    travel_to(at("2026-11-25 09:00")) do
      sign_in_as(coordinator)
      get dashboard_path
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('aria-labelledby="capa-titulo"', "Bom dia, Bruno.", "Precisa de atenção",
      "OS com prazo estourado", "OS em aberto")
    expect(response.body).not_to include("Contas vencidas")
  end

  it "says everything is in order when nothing is pending" do
    sign_in_as(scenario[:coordinator])

    get dashboard_path

    expect(response.body).to include("Precisa de atenção", "Tudo em dia em 5 áreas verificadas")
  end

  describe "overdue receivables" do
    before do
      work_order = travel_to(at("2026-11-20 09:00")) { open_work_order(scenario, title: "Faturada") }
      add_authorized_item(scenario, work_order, unit_price: "800.00")
      travel_to(at("2026-11-20 10:00")) { issue_receivable(scenario, work_order, "800", due_on: Date.new(2026, 11, 21)) }
    end

    def dashboard_for(membership)
      travel_to(at("2026-11-24 10:00")) do
        sign_in_as(membership)
        get dashboard_path
      end
      response.body
    end

    it "shows them only to members allowed to see finance" do
      expect(dashboard_for(member(:finance, name: "Gabriela Financeiro"))).to include("Contas vencidas")

      %i[coordinator attendant technician].each do |role|
        expect(dashboard_for(member(role, name: "Sem Financeiro"))).not_to include("Contas vencidas"), role.to_s
      end
    end

    it "hides them when the plan does not include the finance module" do
      in_tenant(organization) do
        plan = Plan.find_by!(code: "profissional")
        Subscription.create!(organization:, plan:, status: "active", technician_seats: plan.included_technicians,
          monthly_amount: plan.monthly_price, activated_at: Time.current)
      end

      expect(dashboard_for(member(:owner, name: "Ana Proprietária"))).not_to include("Contas vencidas")
    end
  end

  it "shows a technician only their own visits, never the whole agenda", :aggregate_failures do
    diego = create_technician(organization, name: "Diego Técnico")
    elisa = create_technician(organization, name: "Elisa Técnica")
    schedule(scenario, order_for("Padaria do Diego"), [diego], from: tuesday_at(14), to: tuesday_at(15), travel: 0)
    schedule(scenario, order_for("Hotel da Elisa"), [elisa], from: tuesday_at(14), to: tuesday_at(15), travel: 0)
    schedule(scenario, order_for("Clínica da Elisa"), [elisa], from: tuesday_at(16), to: tuesday_at(17), travel: 0)

    travel_to(tuesday_at(9)) do
      sign_in_as(diego)
      get dashboard_path
    end

    body = response.body
    expect(body).to include("Bom dia, Diego.", "Padaria do Diego", "1 visita hoje")
    expect(body).not_to include("Hotel da Elisa", "Clínica da Elisa", "3 visitas hoje")
    expect(body).not_to include("OS em aberto", "OS com prazo")
  end

  describe "charts" do
    let(:chart_titles) { ["OS por situação", "Recebido · últimos 7 dias"] }

    def dashboard_for(membership)
      travel_to(tuesday_at(10)) do
        sign_in_as(membership)
        get dashboard_path
      end
      response.body
    end

    def received_today(amount)
      work_order = travel_to(tuesday_at(8)) { open_work_order(scenario, title: "Faturada") }
      add_authorized_item(scenario, work_order, unit_price: amount)
      travel_to(tuesday_at(9)) do
        receivable = issue_receivable(scenario, work_order, amount, due_on: Date.new(2026, 12, 20))
        pay(receivable, amount)
      end
    end

    it "shows each chart only to the members allowed to read it", :aggregate_failures do
      visible = {
        owner: ["OS por situação", "Recebido · últimos 7 dias"],
        finance: ["OS por situação", "Recebido · últimos 7 dias"],
        coordinator: ["OS por situação"],
        attendant: ["OS por situação"],
        technician: []
      }

      visible.each do |role, titles|
        body = dashboard_for(member(role, name: "Pessoa #{role}"))
        charts = chart_titles.select { |title| body.include?(title) }
        expect(charts).to eq(titles), role.to_s
      end
    end

    it "drops the receipts chart when the plan does not include finance" do
      in_tenant(organization) do
        plan = Plan.find_by!(code: "profissional")
        Subscription.create!(organization:, plan:, status: "active", technician_seats: plan.included_technicians,
          monthly_amount: plan.monthly_price, activated_at: Time.current)
      end

      body = dashboard_for(member(:owner, name: "Ana Proprietária"))

      expect(body).to include("OS por situação")
      expect(body).not_to include("Recebido · últimos 7 dias")
    end

    it "says so when there is nothing to chart" do
      body = dashboard_for(member(:owner, name: "Ana Proprietária"))

      expect(body).to include("Nenhuma ordem de serviço em aberto.", "Nenhum recebimento nos últimos 7 dias.")
      expect(body).not_to include("Ver dados")
    end

    context "with open orders and money received today" do
      let(:page) do
        received_today("1250.00")
        in_tenant(organization) { WorkOrder.last.update_columns(status: "in_progress") }
        Nokogiri::HTML(dashboard_for(member(:finance, name: "Gabriela Financeiro")))
      end

      it "draws the open orders as a labelled SVG bar in the status hue, with its data table" do
        bar = page.at_css('svg[role="img"][aria-label^="OS em aberto por situação"]')

        expect(bar["aria-label"]).to eq("OS em aberto por situação: 1 em execução.")
        expect(bar.css("rect.fill-ember-500").size).to eq(1)
        expect(page.at_css("table caption:contains('Ordens de serviço em aberto por situação')")).to be_present
      end

      it "draws today's receipts in ruby, summarised for assistive technology, with its data table" do
        chart = page.css("figure").find { |figure| figure.at_css("figcaption").text.start_with?("Recebido nos últimos 7 dias") }

        expect(chart.at_css("figcaption").text).to include("R$ 1.250,00", "Hoje: R$ 1.250,00")
        expect(chart.css("path.fill-brand-600").size).to eq(1)
        expect(chart.css("path.fill-ink-300")).to be_empty
        expect(page.css("details summary").map { |summary| summary.text.strip }.count("Ver dados")).to eq(2)
        expect(page.at_css("table caption:contains('Recebido por dia')").parent.text).to include("(hoje)", "R$ 1.250,00")
      end
    end
  end
end
