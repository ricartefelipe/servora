# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }

  def change(contract, to, reason: nil)
    as_member(coordinator) { Contracts::ChangeStatus.new(contract:, to:, actor: coordinator, reason:).call }
  end

  def revise(contract, reason: nil, service_type_ids: [], **attributes)
    as_member(coordinator) do
      Contracts::Save.new(organization:, contract:, actor: coordinator, attributes:, reason:, service_type_ids:).call
    end
  end

  it "versions every change of terms and requires a reason once in force" do
    contract = create_contract(scenario)

    expect { revise(contract, monthly_fee: "950") }.to raise_error(Contracts::Errors::Invalid, /motivo/)
    expect(reload_in_tenant(contract).monthly_fee).to eq(900)
    revise(contract, monthly_fee: "950", reason: "Reajuste anual")
    revise(contract, monthly_fee: "950", reason: "Sem mudança")

    versions = in_tenant(organization) { ContractVersion.where(contract_id: contract.id).order(:version_number).to_a }
    expect(versions.map { |version| [version.version_number, version.terms["monthly_fee"]] }).to eq([[1, "900.0"], [2, "950.0"]])
    expect(versions.last.reason).to eq("Reajuste anual")
    expect(contract.number).to match(/\ACTR-2026-\d{5}\z/)
  end

  it "follows the lifecycle with reasons and deactivates plans when ended" do
    contract = create_contract(scenario)
    plan = create_plan(scenario, contract)

    expect { change(contract, "suspended") }.to raise_error(Contracts::Errors::Invalid, /motivo/)
    change(contract, "suspended", reason: "Inadimplência")
    change(contract, "active")
    change(contract, "ended", reason: "Fim da parceria")

    expect(reload_in_tenant(contract)).to have_attributes(status: "ended", status_reason: "Fim da parceria")
    expect(reload_in_tenant(plan).active).to be(false)
    expect { change(contract, "active") }.to raise_error(Contracts::Errors::Invalid, /Encerrado para Vigente/)
    expect { revise(contract, title: "Outro", reason: "x") }.to raise_error(Contracts::Errors::Invalid, /encerrados/)
  end

  describe Contracts::Coverage do
    it "links new work orders to the contract in force and applies the monthly limit" do
      create_contract(scenario, monthly_visit_limit: 1, service_type_ids: [])
      travel_to Time.zone.local(2026, 3, 10, 9) do
        first = open_work_order(scenario)
        second = open_work_order(scenario, title: "Segunda")

        coverage = in_tenant(organization) { [first, second].map { |order| described_class.new(order.reload).call } }
        expect(first.contract_id).to be_present
        expect(coverage.map(&:covered)).to eq([true, false])
        expect(coverage.last).to have_attributes(reason: /Limite mensal/, used: 1, limit: 1)
      end
    end

    it "does not cover service types outside the contract" do
      other_type = create(:service_type, organization:)
      contract = create_contract(scenario)
      revise(contract, reason: "Escopo", service_type_ids: [other_type.id])

      travel_to Time.zone.local(2026, 3, 10, 9) do
        order = open_work_order(scenario)
        result = in_tenant(organization) { described_class.new(order.reload).call }

        expect(result).to have_attributes(covered: false, reason: /não coberto/)
      end
    end

    it "leaves work orders without contract when none is in force" do
      create_contract(scenario, status: "draft")

      expect(open_work_order(scenario).contract_id).to be_nil
    end
  end
end
