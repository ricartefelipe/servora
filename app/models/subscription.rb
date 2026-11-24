# frozen_string_literal: true

# The organization's platform subscription. Changed only through
# Subscriptions::* use cases.
class Subscription < TenantRecord
  STATUSES = { "trialing" => "Avaliação", "active" => "Ativa", "past_due" => "Pagamento pendente",
               "canceled" => "Cancelada" }.freeze

  belongs_to :plan
  has_many :invoices, class_name: "SubscriptionInvoice", dependent: nil, inverse_of: :subscription

  def status_label = STATUSES.fetch(status)
  def trial_expired?(today = Time.zone.today) = status == "trialing" && trial_ends_on < today
  def trial_days_left(today = Time.zone.today) = status == "trialing" ? [(trial_ends_on - today).to_i, 0].max : 0

  # Writes are blocked after the trial ends without activation and while the
  # subscription is past due or canceled; reading stays available.
  def read_only?(today = Time.zone.today) = trial_expired?(today) || %w[past_due canceled].include?(status)

  # During the trial every module is available, so the whole product can be evaluated.
  def module_enabled?(code) = status == "trialing" || plan.pricing.modules(addon_modules).include?(code.to_s)
end
