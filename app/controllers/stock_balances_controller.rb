# frozen_string_literal: true

class StockBalancesController < TenantController
  requires_module :inventory

  def index
    authorize StockBalance
    @warehouses = policy_scope(tenant_relation(Warehouse)).alphabetical
    @warehouse = @warehouses.find_by(id: params[:deposito]) if params[:deposito].present?
    query = StockBalanceSearchQuery.new(policy_scope(tenant_relation(StockBalance)), warehouse: @warehouse, term: params[:q],
      below_minimum: params[:abaixo] == "1")
    @summary = query.summary
    @pagination = Pagination.new(query.call, page: params[:pagina], per_page: 50)
  end

  def minimum
    authorize StockBalance, :set_minimum?
    attributes = params.expect(stock_minimum: %i[warehouse_id catalog_item_id minimum])
    warehouse = policy_scope(tenant_relation(Warehouse)).find(attributes[:warehouse_id])
    item = tenant_relation(CatalogItem).stockable.find(attributes[:catalog_item_id])
    Inventory::SetMinimum.new(warehouse:, item:, minimum: attributes[:minimum], actor: current_membership).call
    redirect_to stock_balances_path(deposito: warehouse.id), notice: "Estoque mínimo de #{item.name} atualizado.",
      status: :see_other
  rescue Servora::RuleViolation, Pricing::Amount::InvalidValue => e
    redirect_to stock_balances_path, alert: e.is_a?(Servora::RuleViolation) ? e.message : "Informe um número válido.",
      status: :see_other
  end
end
