# frozen_string_literal: true

module WorkOrderHelpers
  def build_work_order_scenario(organization: create(:organization))
    coordinator = create(:membership, :coordinator, organization:)
    technician = create(:membership, :technician, organization:)
    customer = create(:customer, organization:)
    location = create(:service_location, customer:)
    equipment = create(:equipment, location:)
    approver = create(:customer_contact, customer:, can_approve: true)
    service_type = create(:service_type, organization:)
    { organization:, coordinator:, technician:, customer:, location:, equipment:, approver:, service_type: }
  end

  def open_work_order(scenario, **overrides)
    attributes = { title: "Split não gela", problem_description: "Equipamento liga mas não refrigera.", origin: "phone",
                   priority: "high", customer_id: scenario[:customer].id, service_location_id: scenario[:location].id,
                   service_type_id: scenario[:service_type].id }.merge(overrides)
    as_member(scenario[:coordinator]) do
      WorkOrders::Create.new(organization: scenario[:organization], actor: scenario[:coordinator], attributes:,
        equipment_ids: [scenario[:equipment].id]).call
    end
  end

  def ready_to_complete!(scenario, work_order)
    in_tenant(scenario[:organization]) do
      work_order.checklist_items.each do |item|
        next unless item.required

        item.update!(response: item.response_kind == "number" ? "68" : "sim")
      end
      work_order.update!(diagnosis: "Filtro obstruído e baixa carga de gás", solution: "Limpeza e recarga")
      WorkOrders::Transition.new(work_order: work_order.reload, to: "in_progress", actor: scenario[:coordinator]).call
    end
  end
end

RSpec.configure do |config|
  config.include WorkOrderHelpers
end
