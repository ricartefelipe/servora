# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory policies" do # rubocop:disable RSpec/DescribeClass -- groups the inventory policies
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:technician) { scenario[:technician] }
  let!(:central) { create(:warehouse, organization:, name: "Central") }
  let!(:own_van) { create(:warehouse, organization:, name: "Van própria", kind: "vehicle", custodian: technician) }
  let!(:other_van) { create(:warehouse, :vehicle, organization:, name: "Van de outro técnico") }

  def context(membership) = PolicyContext.new(user: membership.user, membership:)
  def member(role) = create(:membership, role.to_sym, organization:)

  def visible_warehouses(membership)
    in_tenant(organization) { WarehousePolicy::Scope.new(context(membership), Warehouse.all).resolve.order(:name).map(&:name) }
  end

  it "shows technicians only the warehouses in their custody" do
    expect(visible_warehouses(technician)).to eq(["Van própria"])
    expect(visible_warehouses(scenario[:coordinator])).to contain_exactly(central.name, own_van.name, other_van.name)
    expect(visible_warehouses(member(:auditor)).size).to eq(3)
  end

  it "applies the warehouse visibility to balances and movements" do
    item = stock_part(organization)
    receive_stock(central, item, "1", "10")
    receive_stock(own_van, item, "1", "10")

    in_tenant(organization) do
      balances = StockBalancePolicy::Scope.new(context(technician), StockBalance.all).resolve
      movements = StockMovementPolicy::Scope.new(context(technician), StockMovement.all).resolve

      expect(balances.pluck(:warehouse_id)).to eq([own_van.id])
      expect(movements.pluck(:warehouse_id)).to eq([own_van.id])
    end
  end

  it "separates moving stock, adjusting it and seeing its cost" do
    matrix = %i[owner coordinator attendant technician finance auditor].to_h do |role|
      membership = role == :technician ? technician : member(role)
      policy = StockBalancePolicy.new(context(membership), StockBalance)
      [role, [policy.receive?, policy.adjust?, policy.view_costs?]]
    end

    expect(matrix).to eq(owner: [true, true, true], coordinator: [true, false, false], attendant: [false, false, false],
      technician: [false, false, false], finance: [false, false, true], auditor: [false, false, true])
    expect(WarehousePolicy.new(context(scenario[:coordinator]), Warehouse).create?).to be(false)
  end

  it "lets the assigned technician consume but not reserve or return material" do
    work_order = open_work_order(scenario)
    in_tenant(organization) { WorkOrders::Assign.new(work_order:, membership: technician).call }
    loaded = in_tenant(organization) { WorkOrder.includes(:assignments).find(work_order.id) }
    technician_policy = WorkOrderPolicy.new(context(technician), loaded)
    coordinator_policy = WorkOrderPolicy.new(context(scenario[:coordinator]), loaded)

    expect([technician_policy.consume_material?, technician_policy.reserve_material?, technician_policy.return_material?])
      .to eq([true, false, false])
    expect([coordinator_policy.consume_material?, coordinator_policy.reserve_material?, coordinator_policy.view_materials?])
      .to eq([true, true, true])
  end
end
