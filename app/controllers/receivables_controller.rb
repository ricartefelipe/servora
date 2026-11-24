# frozen_string_literal: true

class ReceivablesController < TenantController
  include ModalForms

  FILTERS = %w[open partially_paid paid canceled overdue].freeze

  before_action :load_receivable, only: %i[show cancel]

  def index
    authorize Receivable
    scope = policy_scope(current_organization.receivables)
    @filter = params[:situacao].presence_in(FILTERS) # rubocop:disable Rails/StrongParametersExpect -- optional filter
    @summary = ReceivablesSummaryQuery.new(scope).call
    @pagination = Pagination.new(filtered(scope).includes(:customer, :work_order).recent_first, page: params[:pagina],
      per_page: 50)
  end

  def show
    authorize @receivable
    @payments = tenant_relation(Payment).where(receivable_id: @receivable.id).includes(recorded_by: :user).order(:paid_at)
    @charges = tenant_relation(PaymentCharge).where(receivable_id: @receivable.id).order(created_at: :desc).to_a
    @events = tenant_relation(FinancialEvent).where(receivable_id: @receivable.id).order(:occurred_at, :id)
    @integration = PaymentIntegration.for(current_organization.id)
  end

  def new
    @work_order = billable_work_order(params.expect(:ordem))
    @form = ReceivableForm.new(work_order_id: @work_order.id, due_on: 7.days.from_now.to_date.iso8601,
      amount: WorkOrderFinancialsQuery.new(@work_order).remaining_to_bill.to_s("F"))
  end

  def create
    @form = ReceivableForm.new(params.expect(receivable: ReceivableForm.fields))
    @work_order = billable_work_order(@form.work_order_id)
    return invalid unless @form.valid?

    receivable = Receivables::Issue.new(work_order: @work_order, amount: @form.amount, due_on: @form.due_on,
      description: @form.description, actor: current_membership).call
    redirect_to receivable_path(receivable), notice: "Conta #{receivable.number} emitida.", status: :see_other
  rescue Servora::RuleViolation, Pricing::Amount::InvalidValue => e
    @form.errors.add(:base, e.is_a?(Servora::RuleViolation) ? e.message : "Informe um valor válido.")
    invalid
  end

  def cancel
    authorize @receivable
    Receivables::Cancel.new(receivable: @receivable, reason: params.expect(cancellation: [:reason])[:reason],
      actor: current_membership).call
    redirect_to receivable_path(@receivable), notice: "Conta cancelada.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to receivable_path(@receivable), alert: e.message, status: :see_other
  end

  private

  def load_receivable
    @receivable = policy_scope(tenant_relation(Receivable)).includes(:customer, :work_order).find(params.expect(:id))
  end

  def billable_work_order(id)
    work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(id)
    authorize work_order, :bill?
    work_order
  end

  def filtered(scope)
    case @filter
    when "overdue" then scope.overdue
    when nil then scope
    else scope.where(status: @filter)
    end
  end

  def invalid
    render_invalid_form(partial: "receivables/form", template: :new, form: @form, work_order: @work_order)
  end
end
