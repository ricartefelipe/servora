# frozen_string_literal: true

module WorkOrders
  class StockReservationsController < TenantController
    requires_module :inventory

    include WorkOrderMaterials

    def create
      authorize @work_order, :reserve_material?
      attributes = params.expect(reservation: %i[warehouse_id catalog_item_id quantity])
      warehouse = operable_warehouses.find(attributes[:warehouse_id])
      item = stockable_items.find(attributes[:catalog_item_id])
      Inventory::Reserve.new(work_order: @work_order, warehouse:, item:, quantity: attributes[:quantity],
        actor: current_membership).call
      back_to_materials(notice: "#{item.name} reservado para a ordem.")
    end

    def release
      authorize @work_order, :release_material?
      reservation = tenant_relation(StockReservation).where(work_order_id: @work_order.id).find(params.expect(:id))
      Inventory::ReleaseReservation.new(reservation:, actor: current_membership, reason: "Liberação manual").call
      back_to_materials(notice: "Saldo reservado devolvido ao disponível.")
    end
  end
end
