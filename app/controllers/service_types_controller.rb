# frozen_string_literal: true

class ServiceTypesController < TenantController
  before_action :load_service_type, only: %i[edit update]

  def index
    authorize ServiceType
    @service_types = policy_scope(current_organization.service_types).includes(:checklist_items).alphabetical
  end

  def new
    @service_type = current_organization.service_types.new
    authorize @service_type, :create?
    3.times { |index| @service_type.checklist_items.build(position: index + 1, organization: current_organization) }
  end

  def edit
    @service_type.checklist_items.build(position: @service_type.checklist_items.size + 1, organization: current_organization)
  end

  def create
    @service_type = current_organization.service_types.new(service_type_params)
    authorize @service_type, :create?
    assign_tenant_to_items
    if @service_type.save
      redirect_to service_types_path, notice: "Tipo de serviço criado."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @service_type.assign_attributes(service_type_params)
    assign_tenant_to_items
    if @service_type.save
      redirect_to service_types_path, notice: "Tipo de serviço atualizado. Ordens já abertas mantêm o checklist original."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_service_type
    @service_type = policy_scope(tenant_relation(ServiceType)).includes(:checklist_items).find(params.expect(:id))
    authorize @service_type, :update?
  end

  def assign_tenant_to_items
    @service_type.checklist_items.each { |item| item.organization_id = current_organization.id }
  end

  def service_type_params
    params.expect(service_type: [:name, :description, :active,
                                 { checklist_items_attributes: [%i[id label response_kind required position _destroy]] }])
  end
end
