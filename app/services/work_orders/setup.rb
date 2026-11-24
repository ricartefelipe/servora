# frozen_string_literal: true

module WorkOrders
  # Links equipment (must belong to the work order's customer; enforced by a
  # composite foreign key) and copies the service type checklist.
  class Setup
    def initialize(work_order:, equipment_ids: [])
      @work_order = work_order
      @equipment_ids = equipment_ids
    end

    def call
      @equipment_ids.uniq.each do |equipment_id|
        @work_order.work_order_equipment.create!(organization_id: @work_order.organization_id,
          customer_id: @work_order.customer_id, equipment_id:)
      end
      copy_checklist
    end

    private

    def copy_checklist
      return unless @work_order.service_type

      @work_order.service_type.checklist_items.each do |item|
        @work_order.checklist_items.create!(organization_id: @work_order.organization_id, label: item.label,
          response_kind: item.response_kind, required: item.required, position: item.position)
      end
    end
  end
end
