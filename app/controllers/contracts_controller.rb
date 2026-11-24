# frozen_string_literal: true

class ContractsController < TenantController
  FIELDS = %i[customer_id title starts_on ends_on monthly_fee monthly_visit_limit covers_parts scope].freeze

  before_action :load_contract, only: %i[show edit update change_status]

  def index
    authorize Contract
    @status = params[:situacao].presence_in(Contract::STATUSES.keys) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    scope = policy_scope(current_organization.contracts).includes(:customer).recent_first
    scope = scope.where(status: @status) if @status
    @pagination = Pagination.new(scope, page: params[:pagina])
  end

  def show
    authorize @contract
    @plans = tenant_relation(MaintenancePlan).where(contract_id: @contract.id).includes(:service_location).order(:title)
    @versions = tenant_relation(ContractVersion).where(contract_id: @contract.id).includes(created_by: :user)
      .order(version_number: :desc)
    load_orders
  end

  def new
    authorize Contract, :create?
    @contract = current_organization.contracts.new(starts_on: Time.zone.today, customer_id: params[:cliente].presence)
    load_form_options
  end

  def edit
    authorize @contract, :update?
    load_form_options
  end

  def create
    authorize Contract, :create?
    @contract = save_contract(nil)
    redirect_to contract_path(@contract), notice: "Contrato #{@contract.number} criado como rascunho.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    invalid(:new, e.record)
  end

  def update
    authorize @contract, :update?
    save_contract(@contract)
    redirect_to contract_path(@contract), notice: "Contrato atualizado (versão #{@contract.current_version}).", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    invalid(:edit, e.record)
  rescue Servora::RuleViolation => e
    flash.now[:alert] = e.message
    invalid(:edit, @contract)
  end

  def change_status
    authorize @contract
    attributes = params.expect(status_change: %i[to reason])
    Contracts::ChangeStatus.new(contract: @contract, to: attributes[:to], reason: attributes[:reason],
      actor: current_membership).call
    redirect_to contract_path(@contract), notice: "Contrato #{@contract.status_label.downcase}.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to contract_path(@contract), alert: e.message, status: :see_other
  end

  private

  def load_orders
    orders = tenant_relation(WorkOrder).where(contract_id: @contract.id)
    @usage = orders.where.not(status: "canceled").where(requested_at: Time.zone.today.beginning_of_month.in_time_zone..).count
    @recent_orders = orders.order(requested_at: :desc).limit(10)
  end

  def load_contract
    @contract = policy_scope(tenant_relation(Contract)).includes(:customer, :contract_service_types).find(params.expect(:id))
  end

  def save_contract(contract)
    attributes = params.expect(contract: [*FIELDS, :reason, { service_type_ids: [] }])
    attributes[:customer_id] = policy_scope(tenant_relation(Customer)).find(attributes[:customer_id]).id unless contract
    Contracts::Save.new(organization: current_organization, contract:, actor: current_membership,
      attributes: attributes.except(:reason, :service_type_ids), reason: attributes[:reason],
      service_type_ids: attributes[:service_type_ids]).call
  end

  def invalid(template, record)
    @contract = record.is_a?(Contract) ? record : @contract
    load_form_options
    render template, status: :unprocessable_content
  end

  def load_form_options
    @customers = policy_scope(current_organization.customers).active.alphabetical if @contract.new_record?
    @service_types = tenant_relation(ServiceType).active.alphabetical
  end
end
