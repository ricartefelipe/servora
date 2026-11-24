# frozen_string_literal: true

module Stock
  # Shared flow of the stock operation modals: options come from policy scopes
  # and the same scopes resolve the submitted identifiers.
  class BaseController < TenantController
    include ModalForms

    private

    def submit(form, notice:)
      if form.submit(warehouses: operable_warehouses, items: stockable_items, actor: current_membership)
        redirect_to stock_balances_path(deposito: form.warehouse_id), notice:, status: :see_other
      else
        load_options
        render_invalid_form(partial: "#{controller_path}/form", template: :new, form:, warehouses: @warehouses, items: @items)
      end
    end

    def load_options
      @warehouses = operable_warehouses.alphabetical
      @items = stockable_items.active.alphabetical
    end

    def operable_warehouses = policy_scope(tenant_relation(Warehouse)).active
    def stockable_items = tenant_relation(CatalogItem).stockable

    def preselection
      { warehouse_id: params[:deposito].presence, catalog_item_id: params[:item].presence }
    end
  end
end
