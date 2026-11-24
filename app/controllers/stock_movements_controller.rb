# frozen_string_literal: true

# Inventory ledger: every movement with the balance it produced.
class StockMovementsController < TenantController
  requires_module :inventory

  def index
    authorize StockMovement
    @warehouses = policy_scope(tenant_relation(Warehouse)).alphabetical
    @warehouse = @warehouses.find_by(id: params[:deposito]) if params[:deposito].present?
    @kind = params[:tipo].presence_in(StockMovement::KIND_LABELS.keys) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    @pagination = Pagination.new(movements, page: params[:pagina], per_page: 50)
  end

  private

  def movements
    relation = policy_scope(tenant_relation(StockMovement)).includes(:warehouse, :catalog_item, :work_order, actor: :user)
      .recent_first
    relation = relation.where(warehouse_id: @warehouse.id) if @warehouse
    relation = relation.where(kind: @kind) if @kind
    relation = relation.where(catalog_item_id: params[:item]) if Servora::Tenancy::UUID_FORMAT.match?(params[:item].to_s)
    relation
  end
end
