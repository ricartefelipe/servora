# frozen_string_literal: true

class CustomersController < TenantController
  before_action :load_customer, only: %i[show edit update archive restore]

  def index
    authorize Customer
    scope = policy_scope(current_organization.customers)
    @query = { term: params[:q], status: params[:situacao].presence || "ativos" }
    @pagination = Pagination.new(Customers::SearchQuery.new(scope, **@query).call, page: params[:pagina])
    @counts = load_counts(@pagination.records)
  end

  def show
    @locations = @customer.service_locations.order(Arel.sql("archived_at IS NOT NULL"), :name)
    @contacts = @customer.contacts.order(Arel.sql("archived_at IS NOT NULL"), :name)
    @equipment = policy_scope(@customer.equipment).active.includes(:service_location).order(:equipment_type)
    events = current_organization.equipment_events
    @history = events.joins(:equipment).where(equipment: { customer_id: @customer.id })
      .or(events.joins(:equipment).where(from_customer_id: @customer.id))
      .includes(:equipment).order(occurred_at: :desc).limit(20)
  end

  def new
    authorize Customer, :create?
    @registration = CustomerRegistration.new
  end

  def edit; end

  def create
    authorize Customer, :create?
    @registration = CustomerRegistration.new(registration_params)
    if @registration.save(organization: current_organization)
      redirect_to customer_path(@registration.customer), notice: "Cliente cadastrado."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @customer.update(customer_params)
      AuditEvent.record!(action: "customer.updated", auditable: @customer, changes: @customer.saved_changes.except("updated_at"))
      redirect_to customer_path(@customer), notice: "Dados do cliente atualizados."
    else
      render :edit, status: :unprocessable_content
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_customer_path(@customer), alert: "O cadastro foi alterado por outra pessoa. Revise e salve novamente."
  end

  def archive
    Customers::Archive.new(customer: @customer).call
    redirect_to customer_path(@customer), notice: "Cliente arquivado."
  end

  def restore
    Customers::Restore.new(customer: @customer).call
    redirect_to customer_path(@customer), notice: "Cliente reativado."
  end

  private

  def load_customer
    @customer = policy_scope(current_organization.customers).find(params.expect(:id))
    authorize @customer, :"#{action_name == "edit" ? "update" : action_name}?"
  end

  def load_counts(customers)
    ids = customers.map(&:id)
    {
      locations: current_organization.service_locations.active.where(customer_id: ids).group(:customer_id).count,
      equipment: current_organization.equipment.active.where(customer_id: ids).group(:customer_id).count
    }
  end

  def registration_params
    params.expect(customer: CustomerRegistration::CUSTOMER_FIELDS + CustomerRegistration::LOCATION_FIELDS +
      CustomerRegistration::CONTACT_FIELDS)
  end

  def customer_params
    params.expect(customer: %i[kind name trade_name document email phone notes lock_version])
  end
end
