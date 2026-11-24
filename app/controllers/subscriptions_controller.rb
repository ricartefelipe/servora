# frozen_string_literal: true

# Platform subscription of the organization (owner only). Platform billing is
# handled outside Servora in this version: activating records the decision and
# the amount that will be invoiced.
class SubscriptionsController < TenantController
  before_action :load_subscription

  def show
    @plans = Plan.ordered
    @modules = PlanModule.ordered
    @seats_in_use = Subscriptions::Seats.in_use(current_organization.id)
    @invoices = tenant_relation(SubscriptionInvoice).where(subscription_id: @subscription.id).recent_first.limit(24)
    @simulated_billing = Payments::Gateways.platform_provider == "simulator"
  end

  # Available only when the platform bills through the simulator (development
  # and demonstrations).
  def simulate_invoice_payment
    return head(:not_found) unless Payments::Gateways.platform_provider == "simulator"

    invoice = tenant_relation(SubscriptionInvoice).where(subscription_id: @subscription.id).find(params.expect(:id))
    raise Servora::RuleViolation, "A cobrança desta fatura ainda não foi registrada." unless invoice.charge_status == "submitted"

    Subscriptions::ConfirmInvoice.new(organization_id: current_organization.id, invoice_id: invoice.id,
      actor: current_membership).call
    redirect_to subscription_path, notice: "Pagamento da fatura confirmado.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to subscription_path, alert: e.message, status: :see_other
  end

  def update
    attributes = params.expect(subscription: [:plan_code, :seats, { addons: [] }])
    Subscriptions::Change.new(subscription: @subscription, plan_code: attributes[:plan_code], seats: attributes[:seats],
      addons: attributes[:addons], actor: current_membership, activate: params[:ativar] == "1").call
    redirect_to subscription_path, notice: "Assinatura atualizada.", status: :see_other
  rescue Servora::RuleViolation => e
    redirect_to subscription_path, alert: e.message, status: :see_other
  end

  private

  def load_subscription
    @subscription = Subscription.includes(:plan).find_by(organization_id: current_organization.id) ||
                    Subscriptions::StartTrial.new(organization: current_organization).call
    authorize @subscription
  end
end
