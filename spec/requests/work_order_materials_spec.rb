# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Work order materials" do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let(:technician) { scenario[:technician] }
  let!(:work_order) { open_work_order(scenario) }
  let!(:central) { create(:warehouse, organization:, name: "Almoxarifado central") }
  let!(:item) { stock_part(organization, name: "Filtro secador") }

  before { receive_stock(central, item, "5", "18") }

  def reserve(quantity)
    post work_order_stock_reservations_path(work_order),
      params: { reservation: { warehouse_id: central.id, catalog_item_id: item.id, quantity: } }
  end

  def consume(**attributes)
    post work_order_material_consumptions_path(work_order),
      params: { consumption: { quantity: "1", operation_key: SecureRandom.uuid_v7 }.merge(attributes) }
  end

  it "reserves, consumes from the reservation and releases the rest" do
    sign_in_as(coordinator)

    reserve("3")
    reservation = in_tenant(organization) { StockReservation.sole }
    consume(reservation_id: reservation.id, quantity: "2")
    patch release_work_order_stock_reservation_path(work_order, reservation)

    expect(response).to redirect_to(work_order_path(work_order, anchor: "materiais"))
    expect(position(central, item)).to eq(["3.0", "0.0", "18.0"])
    follow_redirect!
    expect(response.body).to include("Materiais", "Filtro secador", "Encerrada", "Saldo reservado devolvido")
  end

  it "explains why a reservation is refused" do
    sign_in_as(coordinator)

    reserve("8")
    follow_redirect!

    expect(response.body).to include("Saldo disponível insuficiente de Filtro secador: disponível 5, solicitado 8.")
  end

  it "consumes once when the same form is submitted twice and returns at the original cost" do
    sign_in_as(coordinator)
    key = SecureRandom.uuid_v7

    2.times { consume(warehouse_id: central.id, catalog_item_id: item.id, quantity: "2", operation_key: key) }
    consumption = in_tenant(organization) { MaterialConsumption.sole }
    patch restock_work_order_material_consumption_path(work_order, consumption), params: { restock: { quantity: "1" } }

    expect(position(central, item).first).to eq("4.0")
    expect(in_tenant(organization) { consumption.reload.net_quantity }).to eq(1)
  end

  it "asks for a source when neither a reservation nor a warehouse is chosen" do
    sign_in_as(coordinator)

    consume
    follow_redirect!

    expect(response.body).to include("Escolha uma reserva ou informe o depósito e a peça.")
  end

  it "lets the assigned technician consume only from stock in their custody" do
    van = create(:warehouse, organization:, name: "Van do técnico", kind: "vehicle", custodian: technician)
    receive_stock(van, item, "2", "20")
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: technician).call }
    sign_in_as(technician)

    consume(warehouse_id: van.id, catalog_item_id: item.id)
    expect(position(van, item).first).to eq("1.0")

    consume(warehouse_id: central.id, catalog_item_id: item.id)
    expect(response).to have_http_status(:not_found)
    reserve("1")
    expect(response).to have_http_status(:forbidden)
    get work_order_path(work_order)
    expect(response.body).not_to include("Custo total", "R$ 20,0000")
  end
end
