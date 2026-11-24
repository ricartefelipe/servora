# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory screens" do
  let(:organization) { create(:organization) }
  let(:coordinator) { create(:membership, :coordinator, organization:) }
  let(:owner) { create(:membership, :owner, organization:) }
  let!(:central) { create(:warehouse, organization:, name: "Almoxarifado central") }
  let!(:item) { stock_part(organization, name: "Capacitor 35 µF", sku: "CAP-35") }

  def receipt_params(**overrides)
    { stock_receipt: { warehouse_id: central.id, catalog_item_id: item.id, quantity: "10", unit_cost: "12,50",
                       reason: "NF 4521", operation_key: SecureRandom.uuid_v7 }.merge(overrides) }
  end

  it "lists balances, movements and warehouses with the operations allowed to the member" do
    receive_stock(central, item, "3", "10")
    in_tenant(organization) { Inventory::SetMinimum.new(warehouse: central, item:, minimum: "5", actor: nil).call }
    sign_in_as(coordinator)

    get stock_balances_path
    expect(response.body).to include("Capacitor 35 µF", "Abaixo do mínimo", "Entrada", "Transferência")
    expect(response.body).not_to include("Custo médio", "Valor em estoque", new_stock_adjustment_path)

    get stock_movements_path(deposito: central.id)
    expect(response.body).to include("Entrada", "Almoxarifado central")
    get warehouses_path
    expect(response.body).to include("Depósito central")
  end

  it "shows costs and adjustments to the owner" do
    receive_stock(central, item, "2", "10")
    sign_in_as(owner)

    get stock_balances_path

    expect(response.body).to include("Custo médio", "R$ 10,0000", "Valor em estoque", new_stock_adjustment_path)
  end

  it "registers a receipt once even if the form is submitted twice" do
    sign_in_as(coordinator)
    params = receipt_params

    2.times { post stock_receipts_path, params: }

    expect(response).to redirect_to(stock_balances_path(deposito: central.id))
    expect(position(central, item)).to eq(["10.0", "0.0", "12.5"])
    expect(in_tenant(organization) { StockMovement.count }).to eq(1)
  end

  it "renders validation and rule errors back into the form" do
    sign_in_as(coordinator)

    post stock_receipts_path, params: receipt_params(quantity: ""), as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("modal-body", "Quantidade")

    post stock_transfers_path, params: { stock_transfer: { warehouse_id: central.id, destination_id: central.id,
                                                           catalog_item_id: item.id, quantity: "1",
                                                           operation_key: SecureRandom.uuid_v7 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Escolha depósitos diferentes.")
  end

  it "does not accept warehouses or items of another organization" do
    foreign = create(:warehouse, organization: create(:organization))
    sign_in_as(coordinator)

    post stock_receipts_path, params: receipt_params(warehouse_id: foreign.id)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Depósito ou item indisponível")
    expect(in_tenant(foreign.organization_id) { StockBalance.count }).to eq(0)
  end

  it "reserves adjustments and thresholds for roles allowed to adjust stock" do
    receive_stock(central, item, "5", "10")
    sign_in_as(coordinator)
    get new_stock_adjustment_path
    expect(response).to have_http_status(:forbidden)

    sign_in_as(owner)
    post stock_adjustments_path, params: { stock_adjustment: { warehouse_id: central.id, catalog_item_id: item.id, quantity: "2",
                                                               direction: "out", reason: "Avaria no transporte",
                                                               operation_key: SecureRandom.uuid_v7 } }
    patch minimum_stock_balances_path,
      params: { stock_minimum: { warehouse_id: central.id, catalog_item_id: item.id, minimum: "4" } }

    expect(position(central, item).first).to eq("3.0")
    expect(balance_of(central, item).minimum_quantity).to eq(4)
  end

  it "manages warehouses and requires a custodian for vehicles" do
    technician = create(:membership, :technician, organization:)
    sign_in_as(owner)

    post warehouses_path, params: { warehouse: { name: "Van 03", kind: "vehicle" } }, as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Responsável é obrigatório")

    post warehouses_path, params: { warehouse: { name: "Van 03", kind: "vehicle", custodian_membership_id: technician.id } }
    expect(in_tenant(organization) { Warehouse.find_by!(name: "Van 03").custodian_membership_id }).to eq(technician.id)
  end

  it "shows technicians only their own stock and no operations" do
    technician = create(:membership, :technician, organization:)
    van = create(:warehouse, organization:, name: "Van do técnico", kind: "vehicle", custodian: technician)
    receive_stock(van, item, "2", "10")
    receive_stock(central, item, "9", "10")
    sign_in_as(technician)

    get stock_balances_path
    expect(response.body).to include("Van do técnico")
    expect(response.body).not_to include("Almoxarifado central", new_stock_receipt_path)

    post stock_receipts_path, params: receipt_params
    expect(response).to have_http_status(:forbidden)
  end
end
