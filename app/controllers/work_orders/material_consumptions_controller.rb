# frozen_string_literal: true

module WorkOrders
  # Consumption comes either from a reservation of this order (any warehouse)
  # or directly from a warehouse the member may operate — for technicians,
  # only the stock in their custody.
  class MaterialConsumptionsController < TenantController
    include WorkOrderMaterials

    def create
      authorize @work_order, :consume_material?
      attributes = params.expect(consumption: %i[reservation_id warehouse_id catalog_item_id quantity operation_key])
      reservation = reservation_for(attributes[:reservation_id])
      warehouse, item = source_for(reservation, attributes)
      Inventory::Consume.new(work_order: @work_order, actor: current_membership, reservation:, warehouse:, item:,
        quantity: attributes[:quantity], idempotency_key: operation_key(attributes[:operation_key])).call
      back_to_materials(notice: "Consumo registrado na ordem.")
    end

    def restock
      authorize @work_order, :return_material?
      consumption = tenant_relation(MaterialConsumption).where(work_order_id: @work_order.id).find(params.expect(:id))
      Inventory::ReturnConsumption.new(consumption:, quantity: params.expect(restock: [:quantity])[:quantity],
        actor: current_membership, reason: "Devolução de material não utilizado").call
      back_to_materials(notice: "Devolução registrada ao custo original do consumo.")
    end

    private

    def reservation_for(id)
      return nil if id.blank?

      tenant_relation(StockReservation).active.where(work_order_id: @work_order.id).includes(:warehouse, :catalog_item).find(id)
    end

    def source_for(reservation, attributes)
      return [reservation.warehouse, reservation.catalog_item] if reservation
      if attributes[:warehouse_id].blank? || attributes[:catalog_item_id].blank?
        raise Servora::RuleViolation, "Escolha uma reserva ou informe o depósito e a peça."
      end

      [operable_warehouses.find(attributes[:warehouse_id]), stockable_items.find(attributes[:catalog_item_id])]
    end
  end
end
