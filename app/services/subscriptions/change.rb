# frozen_string_literal: true

module Subscriptions
  # Changes plan, technician seats and add-on modules. The monthly amount is
  # recomputed by Subscriptions::Pricing; seats can never go below the active
  # technicians. activate: true ends the trial (platform billing is handled
  # outside Servora in this version).
  class Change
    def initialize(subscription:, plan_code:, seats:, addons:, actor:, activate: false)
      @subscription = subscription
      @plan_code = plan_code
      @seats = Integer(seats, exception: false)
      @addons = Array(addons).compact_blank
      @actor = actor
      @activate = activate
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @subscription.lock!
        plan = Plan.find_by(code: @plan_code) || raise(Servora::RuleViolation, "Plano inválido.")
        validate_seats!
        @subscription.update!(attributes(plan))
        AuditEvent.record!(action: @activate ? "subscription.activated" : "subscription.changed", auditable: @subscription,
          changes: { plan: plan.code, seats: @seats, modules: @subscription.addon_modules,
                     monthly_amount: @subscription.monthly_amount })
        @subscription
      end
    end

    private

    def validate_seats!
      raise Servora::RuleViolation, "Informe a quantidade de técnicos." unless @seats&.positive?

      active = Seats.in_use(@subscription.organization_id)
      return if @seats >= active

      raise Servora::RuleViolation, "Há #{active} técnicos ativos ou convidados; reduza a equipe antes de diminuir as vagas."
    end

    def attributes(plan)
      pricing = plan.pricing
      changes = { plan:, technician_seats: @seats, addon_modules: pricing.billable_addons(@addons),
                  monthly_amount: pricing.monthly_amount(seats: @seats, addons: @addons) }
      return changes unless @activate || @subscription.status == "active"

      changes.merge(status: "active", activated_at: @subscription.activated_at || Time.current, trial_ends_on: nil)
    end
  end
end
