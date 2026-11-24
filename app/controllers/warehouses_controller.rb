# frozen_string_literal: true

class WarehousesController < TenantController
  include ModalForms

  before_action :load_warehouse, only: %i[edit update]

  def index
    authorize Warehouse
    @warehouses = policy_scope(tenant_relation(Warehouse)).includes(custodian: :user).alphabetical
  end

  def new
    @warehouse = current_organization.warehouses.new(kind: "central")
    authorize @warehouse, :create?
    load_custodians
  end

  def edit
    load_custodians
  end

  def create
    @warehouse = current_organization.warehouses.new(warehouse_params)
    authorize @warehouse, :create?
    if @warehouse.save
      AuditEvent.record!(action: "warehouse.created", auditable: @warehouse,
        changes: { name: @warehouse.name, kind: @warehouse.kind })
      redirect_to warehouses_path, notice: "Depósito #{@warehouse.name} cadastrado.", status: :see_other
    else
      invalid(:new)
    end
  end

  def update
    if @warehouse.update(warehouse_params)
      AuditEvent.record!(action: "warehouse.updated", auditable: @warehouse,
        changes: @warehouse.saved_changes.except("updated_at"))
      redirect_to warehouses_path, notice: "Depósito atualizado.", status: :see_other
    else
      invalid(:edit)
    end
  end

  private

  def load_warehouse
    @warehouse = policy_scope(tenant_relation(Warehouse)).find(params.expect(:id))
    authorize @warehouse, :update?
  end

  def load_custodians
    @custodians = tenant_relation(Membership).active.includes(:user).ordered
  end

  def invalid(template)
    load_custodians
    render_invalid_form(partial: "warehouses/form", template:, warehouse: @warehouse, custodians: @custodians)
  end

  def warehouse_params
    attributes = params.expect(warehouse: policy(@warehouse || Warehouse).permitted_attributes)
    attributes[:custodian_membership_id] = nil if attributes[:kind] == "central"
    if attributes[:custodian_membership_id].present?
      attributes[:custodian_membership_id] = tenant_relation(Membership).active.find(attributes[:custodian_membership_id]).id
    end
    attributes
  end
end
