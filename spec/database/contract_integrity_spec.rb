# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract and preventive integrity in PostgreSQL" do
  def in_savepoint(&)
    ActiveRecord::Base.transaction(requires_new: true, &)
  end

  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:contract) { create_contract(scenario) }

  it "refuses a contract of another customer on a work order" do
    other_customer = create(:customer, organization:)
    other_contract = create_contract(scenario.merge(customer: other_customer))
    work_order = open_work_order(scenario)

    in_tenant(organization) do
      expect { in_savepoint { WorkOrder.where(id: work_order.id).update_all(contract_id: other_contract.id) } }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_work_orders_contract_customer/)
    end
  end

  it "refuses plan locations and equipment of another customer" do
    plan = create_plan(scenario, contract)
    foreign_location = create(:service_location, customer: create(:customer, organization:))
    foreign_equipment = create(:equipment, location: foreign_location)

    in_tenant(organization) do
      expect { in_savepoint { MaintenancePlan.where(id: plan.id).update_all(service_location_id: foreign_location.id) } }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_maintenance_plans_location_customer/)
      expect do
        in_savepoint do
          MaintenancePlanEquipment.create!(organization:, maintenance_plan: plan, customer_id: plan.customer_id,
            equipment_id: foreign_equipment.id)
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey, /fk_maintenance_plan_equipment_customer/)
    end
  end

  it "keeps occurrence identity unique per plan" do
    plan = create_plan(scenario, contract)
    generate_occurrences(plan, Date.new(2026, 1, 31))
    work_order = open_work_order(scenario)

    in_tenant(organization) do
      expect do
        in_savepoint do
          MaintenanceOccurrence.create!(organization:, maintenance_plan: plan, sequence: 1, due_on: Date.new(2026, 1, 31),
            work_order:, generated_at: Time.current)
        end
      end.to raise_error(ActiveRecord::RecordNotUnique, /index_maintenance_occurrences_identity/)
    end
  end

  it "keeps contract versions append-only" do
    in_tenant(organization) do
      expect { in_savepoint { ContractVersion.where(contract_id: contract.id).update_all(reason: "x") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end

  it "hides contracts and plans from other organizations" do
    create_plan(scenario, contract)

    in_tenant(create(:organization)) do
      expect([Contract, ContractVersion, MaintenancePlan, MaintenanceOccurrence].map(&:count)).to all(eq(0))
    end
  end
end
