# frozen_string_literal: true

class EquipmentController < TenantController
  include ModalForms

  before_action :load_equipment, except: %i[index new create]

  def index
    authorize Equipment
    scope = policy_scope(current_organization.equipment).includes(:customer, :service_location)
    @filters = { term: params[:q], status: params[:estado], include_archived: params[:arquivados] == "1" }
    @pagination = Pagination.new(EquipmentCatalog::SearchQuery.new(scope, **@filters).call, page: params[:pagina])
  end

  def show
    @events = @equipment.events.limit(50).to_a
    ids = @events.flat_map { |e| [e.from_location_id, e.to_location_id] }.compact.uniq
    @locations_by_id = current_organization.service_locations.where(id: ids).index_by(&:id)
  end

  def new
    authorize Equipment, :create?
    customer_id = params[:customer_id]
    customer = customer_id && policy_scope(current_organization.customers).active.find(customer_id)
    @equipment = current_organization.equipment.new(customer:)
    @customer_options = customer_options
  end

  def edit; end

  def create
    authorize Equipment, :create?
    @equipment = EquipmentLifecycle::Register.new(organization: current_organization, attributes: equipment_params,
      actor: current_membership).call
    redirect_to equipment_path(@equipment), notice: "Equipamento cadastrado."
  rescue ActiveRecord::RecordInvalid => e
    @equipment = e.record
    @customer_options = customer_options
    render :new, status: :unprocessable_content
  end

  def update
    if @equipment.update(equipment_params.except(:customer_id, :service_location_id, :operational_status))
      AuditEvent.record!(action: "equipment.updated", auditable: @equipment,
        changes: @equipment.saved_changes.except("updated_at", "lock_version"))
      redirect_to equipment_path(@equipment), notice: "Equipamento atualizado."
    else
      render :edit, status: :unprocessable_content
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_equipment_path(@equipment), alert: "O equipamento foi alterado por outra pessoa. Revise e salve novamente."
  end

  def move; end

  def relocate
    location = current_organization.service_locations.active.includes(:customer)
      .find(params.expect(relocation: [:service_location_id])[:service_location_id])
    authorize location.customer, :show?
    EquipmentLifecycle::Relocate.new(equipment: @equipment, location:, actor: current_membership,
      reason: params.dig(:relocation, :reason), expected_version: params.dig(:relocation, :lock_version)).call
    redirect_to equipment_path(@equipment), notice: "Localização atualizada.", status: :see_other
  rescue Servora::RuleViolation, ActiveRecord::StaleObjectError => e
    message = e.is_a?(ActiveRecord::StaleObjectError) ? "O equipamento foi alterado por outra pessoa." : e.message
    redirect_to equipment_path(@equipment), alert: message, status: :see_other
  end

  def change_status
    status = params.expect(status_change: %i[operational_status reason])
    EquipmentLifecycle::ChangeStatus.new(equipment: @equipment, status: status[:operational_status], actor: current_membership,
      reason: status[:reason]).call
    redirect_to equipment_path(@equipment), notice: "Estado operacional atualizado.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    redirect_to equipment_path(@equipment), alert: "Estado operacional inválido.", status: :see_other
  end

  def archive
    EquipmentLifecycle::Archive.new(equipment: @equipment, actor: current_membership).call
    redirect_to equipment_path(@equipment), notice: "Equipamento arquivado."
  end

  def restore
    EquipmentLifecycle::Archive.new(equipment: @equipment, actor: current_membership, restore: true).call
    redirect_to equipment_path(@equipment), notice: "Equipamento reativado."
  end

  def destroy
    customer = @equipment.customer
    EquipmentLifecycle::Remove.new(equipment: @equipment).call
    redirect_to customer_path(customer), notice: "Equipamento excluído.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to equipment_path(@equipment), alert: e.message, status: :see_other
  end

  ACTION_PERMISSIONS = { "edit" => :update?, "move" => :relocate?, "relocate" => :relocate?,
                         "change_status" => :change_status? }.freeze
  private_constant :ACTION_PERMISSIONS

  private

  def customer_options
    policy_scope(current_organization.customers).active.alphabetical.limit(500)
  end

  def load_equipment
    @equipment = policy_scope(current_organization.equipment).includes(:customer, :service_location).find(params.expect(:id))
    authorize @equipment, ACTION_PERMISSIONS.fetch(action_name, :"#{action_name}?")
  end

  def equipment_params
    attributes = params.expect(equipment: %i[customer_id service_location_id equipment_type manufacturer model serial_number
                                             asset_tag capacity installed_on warranty_until warranty_notes operational_status
                                             notes lock_version])
    customer_id = attributes[:customer_id]
    if customer_id.present? && !policy_scope(current_organization.customers).active.exists?(id: customer_id)
      raise ActiveRecord::RecordNotFound
    end

    attributes
  end
end
