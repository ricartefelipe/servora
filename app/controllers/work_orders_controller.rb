# frozen_string_literal: true

class WorkOrdersController < TenantController
  STATUS_FILTERS = WorkOrders::States.states
  ORDER_INCLUDES = [
    :customer, :service_location, :service_type, :created_by, :quote_version,
    { work_order_equipment: :equipment, assignments: { membership: :user },
      items: %i[authorized_by_contact authorized_by_membership], checklist_items: :responded_by,
      transitions: [], reports: [], visits: { allocations: { membership: :user } } }
  ].freeze

  FORM_FIELDS = [:service_location_id, :service_type_id, :title, :problem_description, :origin, :priority,
                 :requires_approval, { equipment_ids: [] }].freeze

  before_action :load_work_order, except: %i[index new create]

  def index
    authorize WorkOrder
    @filters = { status: params[:situacao].presence_in(STATUS_FILTERS), term: params[:q] } # rubocop:disable Rails/StrongParametersExpect
    scope = policy_scope(current_organization.work_orders).includes(:customer, :service_location)
    @pagination = Pagination.new(WorkOrders::SearchQuery.new(scope, **@filters).call, page: params[:pagina])
    @counts = policy_scope(current_organization.work_orders).open_work.group(:status).count
  end

  def show
    authorize @work_order
    @catalog = policy_scope(current_organization.catalog_items).active.alphabetical if policy(@work_order).add_item?
    @technicians = current_organization.memberships.technicians.includes(:user).ordered if policy(@work_order).assign?
    return unless policy(@work_order).decide_item?

    @approvers = tenant_relation(CustomerContact).approvers.where(customer_id: @work_order.customer_id)
  end

  def new
    authorize WorkOrder, :create?
    @work_order = current_organization.work_orders.new(origin: "phone", priority: "normal")
    load_form_options
  end

  def create
    authorize WorkOrder, :create?
    work_order = open_work_order(params.expect(work_order: FORM_FIELDS))
    redirect_to work_order_path(work_order), notice: "Ordem de serviço #{work_order.number} aberta."
  rescue ActiveRecord::RecordInvalid => e
    @work_order = e.record.is_a?(WorkOrder) ? e.record : current_organization.work_orders.new
    load_form_options
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_content
  end

  def update_report
    authorize @work_order, :update_execution?
    report = params.expect(report: %i[diagnosis solution lock_version])
    WorkOrders::UpdateTechnicalReport.new(work_order: @work_order, diagnosis: report[:diagnosis], solution: report[:solution],
      expected_version: report[:lock_version]).call
    redirect_to work_order_path(@work_order, anchor: "execucao"), notice: "Diagnóstico e solução salvos.", status: :see_other
  rescue ActiveRecord::StaleObjectError
    redirect_to work_order_path(@work_order, anchor: "execucao"), alert: "Outra pessoa alterou o registro técnico. Revise.",
      status: :see_other
  end

  def change_status
    authorize @work_order
    change = params.expect(status_change: %i[to reason])
    WorkOrders::ChangeStatus.new(work_order: @work_order, to: change[:to], actor: current_membership,
      reason: change[:reason]).call
    redirect_to work_order_path(@work_order), notice: "Situação atualizada para #{@work_order.status_label}.", status: :see_other
  end

  def complete
    authorize @work_order
    WorkOrders::Complete.new(work_order: @work_order, actor: current_membership).call
    redirect_to work_order_path(@work_order), notice: "Ordem de serviço concluída. Relatório registrado.", status: :see_other
  end

  def cancel
    authorize @work_order
    WorkOrders::Cancel.new(work_order: @work_order, actor: current_membership, reason: params.dig(:cancellation, :reason)).call
    redirect_to work_order_path(@work_order), notice: "Ordem de serviço cancelada.", status: :see_other
  end

  def reopen
    authorize @work_order
    WorkOrders::Reopen.new(work_order: @work_order, actor: current_membership, reason: params.dig(:reopening, :reason)).call
    redirect_to work_order_path(@work_order), notice: "Ordem de serviço reaberta. O relatório anterior foi preservado.",
      status: :see_other
  end

  rescue_from Servora::RuleViolation do |error|
    redirect_to work_order_path(@work_order), alert: error.message, status: :see_other
  end

  private

  def load_work_order
    @work_order = policy_scope(tenant_relation(WorkOrder)).includes(*ORDER_INCLUDES).find(params.expect(:id))
  end

  def open_work_order(attributes)
    location = tenant_relation(ServiceLocation).active.includes(:customer).find(attributes[:service_location_id])
    service_type_id = attributes[:service_type_id].presence &&
                      tenant_relation(ServiceType).active.find(attributes[:service_type_id]).id
    WorkOrders::Create.new(
      organization: current_organization, actor: current_membership, equipment_ids: attributes[:equipment_ids],
      requires_approval: attributes[:requires_approval] == "1",
      attributes: attributes.slice(:title, :problem_description, :origin, :priority)
        .merge(customer_id: location.customer_id, service_location_id: location.id, service_type_id:)
    ).call
  end

  def load_form_options
    @customers = policy_scope(current_organization.customers).active.includes(:service_locations, :equipment).alphabetical
    @service_types = current_organization.service_types.active.alphabetical
  end
end
