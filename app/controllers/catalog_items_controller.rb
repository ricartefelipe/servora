# frozen_string_literal: true

class CatalogItemsController < TenantController
  KINDS = %w[service part].freeze

  before_action :load_item, only: %i[edit update]

  def index
    authorize CatalogItem
    @kind = params[:tipo].presence_in(KINDS) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    query = CatalogSearchQuery.new(policy_scope(current_organization.catalog_items), term: params[:q], kind: @kind,
      include_inactive: params[:inativos] == "1")
    @pagination = Pagination.new(query.call, page: params[:pagina], per_page: 50)
  end

  def new
    kind = params[:tipo].presence_in(KINDS) # rubocop:disable Rails/StrongParametersExpect -- optional preselection
    @item = current_organization.catalog_items.new(kind: kind || "service")
    authorize @item, :create?
  end

  def edit; end

  def create
    @item = current_organization.catalog_items.new(item_params)
    authorize @item, :create?
    if @item.save
      AuditEvent.record!(action: "catalog_item.created", auditable: @item,
        changes: { name: @item.name, unit_price: @item.unit_price })
      redirect_to catalog_items_path, notice: "Item incluído no catálogo."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @item.update(item_params)
      AuditEvent.record!(action: "catalog_item.updated", auditable: @item, changes: @item.saved_changes.except("updated_at"))
      redirect_to catalog_items_path, notice: "Item atualizado. Orçamentos já enviados não são afetados."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_item
    @item = policy_scope(tenant_relation(CatalogItem)).find(params.expect(:id))
    authorize @item, :update?
  end

  def item_params
    params.expect(catalog_item: policy(@item || CatalogItem).permitted_attributes)
  end
end
