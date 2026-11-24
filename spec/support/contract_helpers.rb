# frozen_string_literal: true

module ContractHelpers
  def create_contract(scenario, status: "active", starts_on: Date.new(2026, 1, 1), **terms)
    as_member(scenario[:coordinator]) do
      contract = Contracts::Save.new(organization: scenario[:organization], actor: scenario[:coordinator],
        attributes: { customer_id: scenario[:customer].id, title: "Manutenção mensal", starts_on:, monthly_fee: "900" }
            .merge(terms)).call
      contract = Contracts::ChangeStatus.new(contract:, to: "active", actor: scenario[:coordinator]).call if status != "draft"
      contract
    end
  end

  def create_plan(scenario, contract, **attributes)
    as_member(scenario[:coordinator]) do
      Preventive::SavePlan.new(contract:, actor: scenario[:coordinator], equipment_ids: [scenario[:equipment].id],
        attributes: { title: "Preventiva split", service_location_id: scenario[:location].id,
                      service_type_id: scenario[:service_type].id, frequency_unit: "month", frequency_interval: 1,
                      anchor_date: Date.new(2026, 1, 31), lead_days: 0 }.merge(attributes)).call
    end
  end

  def generate_occurrences(plan, today)
    in_tenant(plan.organization_id) { Preventive::GenerateOccurrences.new(plan: plan.reload, today:).call }
  end

  def occurrence_dates(plan)
    in_tenant(plan.organization_id) do
      MaintenanceOccurrence.where(maintenance_plan_id: plan.id).order(:sequence).pluck(:sequence, :due_on)
        .map { |sequence, date| [sequence, date.iso8601] }
    end
  end
end

RSpec.configure do |config|
  config.include ContractHelpers
end
