# frozen_string_literal: true

module Subscriptions
  # Every new organization starts a trial of the most complete plan.
  class StartTrial
    TRIAL_PLAN = "empresarial"

    def initialize(organization:, today: Time.zone.today)
      @organization = organization
      @today = today
    end

    def call
      plan = Plan.find_by!(code: TRIAL_PLAN)
      Subscription.create!(organization_id: @organization.id, plan:, status: "trialing", trial_ends_on: @today + plan.trial_days,
        technician_seats: plan.included_technicians, monthly_amount: plan.monthly_price,
        implementation_fee: plan.implementation_fee,
        implementation_status: plan.implementation_fee.positive? ? "pending" : "not_applicable")
    end
  end
end
