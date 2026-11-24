# frozen_string_literal: true

module WorkOrders
  class ItemsController < TenantController
    before_action :load_work_order

    def create
      authorize @work_order, :add_item?
      attributes = params.expect(item: %i[catalog_item_id description unit unit_price quantity kind])
      catalog_item = attributes[:catalog_item_id].presence &&
                     policy_scope(tenant_relation(CatalogItem)).active.find(attributes[:catalog_item_id])
      WorkOrders::AddItem.new(work_order: @work_order, actor: current_membership, catalog_item:, quantity: attributes[:quantity],
        description: attributes[:description], unit: attributes[:unit].presence || "un",
        unit_price: attributes[:unit_price], kind: attributes[:kind].presence || "service").call
      redirect_to work_order_path(@work_order, anchor: "itens"), notice: "Item adicional incluído e aguardando autorização.",
        status: :see_other
    rescue Pricing::Amount::InvalidValue, ActiveRecord::RecordInvalid
      redirect_to work_order_path(@work_order, anchor: "itens"), alert: "Revise quantidade, preço e descrição.",
        status: :see_other
    end

    def decide
      authorize @work_order, :decide_item?
      item = tenant_relation(WorkOrderItem).where(work_order_id: @work_order.id).find(params.expect(:id))
      decision = params.expect(decision: %i[outcome contact_id channel note])
      contact = tenant_relation(CustomerContact).where(customer_id: @work_order.customer_id).find(decision[:contact_id])
      WorkOrders::DecideItem.new(item:, decision: decision[:outcome], actor: current_membership, contact:,
        channel: decision[:channel], note: decision[:note]).call
      redirect_to work_order_path(@work_order, anchor: "itens"), notice: "Decisão registrada.", status: :see_other
    end

    rescue_from Servora::RuleViolation do |error|
      redirect_to work_order_path(@work_order, anchor: "itens"), alert: error.message, status: :see_other
    end

    private

    def load_work_order
      @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
    end
  end
end
