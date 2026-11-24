# frozen_string_literal: true

# Active platform subscriptions for the demonstration organizations (all
# modules), so the whole product can be demonstrated. Idempotent.
module Seeds
  def self.subscription(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      next if Subscription.exists?

      plan = Plan.find_by!(code: "empresarial")
      Subscription.create!(organization_id:, plan:, status: "active", technician_seats: plan.included_technicians,
        monthly_amount: plan.monthly_price, implementation_fee: plan.implementation_fee, implementation_status: "paid",
        activated_at: Time.current)
    end
  end
end

Seeds.subscription("a")
Seeds.subscription("b")
puts "Assinaturas de demonstração prontas."
