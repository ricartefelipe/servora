# frozen_string_literal: true

# A maintenance contract in force with a monthly preventive plan. The plan's
# next occurrence falls inside its generation window, so the demonstration can
# generate it with "Gerar ocorrências devidas". Idempotent by contract title.
module Seeds
  CONTRACT_TITLE = "Manutenção preventiva — Loja Paulista"

  def self.contracts
    organization_id = ORGANIZATIONS.fetch("a")[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      next if organization.contracts.exists?(title: CONTRACT_TITLE)

      coordinator = Membership.includes(:user).joins(:user)
        .find_by!(organization_id:, users: { email: "bruno@clima-norte.test" })
      Current.set(organization:, membership: coordinator, user: coordinator.user) { seed_contract(organization, coordinator) }
    end
  end

  def self.seed_contract(organization, coordinator)
    customer = Customer.find_by!(organization_id: organization.id, document: "45997418000153")
    service_type = ServiceType.find_by!(organization_id: organization.id, name: "Manutenção preventiva de split")
    contract = Contracts::Save.new(organization:, actor: coordinator, service_type_ids: [service_type.id],
      attributes: { customer_id: customer.id, title: CONTRACT_TITLE, starts_on: Time.zone.today.beginning_of_month,
                    monthly_fee: "1290.00", monthly_visit_limit: 4, covers_parts: false,
                    scope: "Preventiva mensal dos equipamentos de climatização da loja e atendimentos corretivos." }).call
    Contracts::ChangeStatus.new(contract:, to: "active", actor: coordinator).call
    seed_plan(contract, customer, service_type, coordinator)
  end

  def self.seed_plan(contract, customer, service_type, coordinator)
    location = ServiceLocation.find_by!(customer_id: customer.id, name: "Loja Paulista")
    Preventive::SavePlan.new(contract:, actor: coordinator,
      equipment_ids: Equipment.where(service_location_id: location.id).pluck(:id),
      attributes: { title: "Preventiva mensal dos splits", service_location_id: location.id, service_type_id: service_type.id,
                    frequency_unit: "month", frequency_interval: 1, anchor_date: Time.zone.today + 3, lead_days: 7 }).call
  end
end

Seeds.contracts
puts "Contrato e plano preventivo de demonstração prontos."
