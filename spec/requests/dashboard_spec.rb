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
end
