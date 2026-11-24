# frozen_string_literal: true

# Active platform subscriptions for the demonstration organizations (all
# modules), so the whole product can be demonstrated. Idempotent.
#
# Plans are reference data loaded by db:privileges:apply. When db:prepare
# seeds a brand-new database before that step, this file waits for the next
# seed run (bin/db-prepare --seed runs after the privileges).
module Seeds
  def self.subscriptions_ready? = Plan.exists?(code: "empresarial")

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

if Seeds.subscriptions_ready?
  Seeds.subscription("a")
  Seeds.subscription("b")
  puts "Assinaturas de demonstração prontas."
else
  puts "Assinaturas de demonstração aguardando os dados de referência (db:privileges:apply)."
end
