# frozen_string_literal: true

module Portal
  # The customer's equipment and its service history.
  class EquipmentController < BaseController
    def index
      @equipment = customer_scope(Equipment).active.includes(:service_location).order(:equipment_type)
    end

    def show
      @equipment = customer_scope(Equipment).includes(:service_location).find(params.expect(:id))
      @history = customer_scope(WorkOrder).joins(:work_order_equipment)
        .where(work_order_equipment: { equipment_id: @equipment.id }).order(requested_at: :desc).limit(50)
    end
  end
end
