# frozen_string_literal: true

# Demonstration organizations and people. Idempotent: organizations use fixed
# identifiers and people are looked up by e-mail. All addresses use the
# reserved ".test" domain; the shared password is for local demonstration only.
module Seeds
  PASSWORD = ENV.fetch("SEED_PASSWORD", "servora-demo-2026")

  ORGANIZATIONS = {
    "a" => {
      id: "0193a000-0000-7000-8000-00000000000a", name: "Clima Norte Manutenção", legal_name: "Clima Norte Manutenção Ltda.",
      document: "11222333000181", segment: "hvac", travel_buffer_minutes: 30
    },
    "b" => {
      id: "0193b000-0000-7000-8000-00000000000b", name: "Predial Sul Serviços", legal_name: "Predial Sul Serviços Técnicos Ltda.",
      document: "45723174000110", segment: "building", travel_buffer_minutes: 20
    }
  }.freeze

  PEOPLE = {
    "a" => [
      ["Ana Ribeiro", "ana@clima-norte.test", "owner", nil],
      ["Bruno Costa", "bruno@clima-norte.test", "coordinator", nil],
      ["Carla Mendes", "carla@clima-norte.test", "attendant", nil],
      ["Diego Alves", "diego@clima-norte.test", "technician", "62.50"],
      ["Eduarda Lima", "eduarda@clima-norte.test", "technician", "58.00"],
      ["Fábio Souza", "fabio@clima-norte.test", "technician", "55.00"],
      ["Gabriela Rocha", "gabriela@clima-norte.test", "finance", nil],
      ["Heitor Nunes", "heitor@clima-norte.test", "auditor", nil]
    ],
    "b" => [
      ["Igor Martins", "igor@predial-sul.test", "owner", nil],
      ["Júlia Freitas", "julia@predial-sul.test", "technician", "48.00"]
    ]
  }.freeze

  def self.user(name, email)
    User.find_or_initialize_by(email:).tap do |user|
      next if user.persisted?

      user.assign_attributes(name:, password: PASSWORD, password_confirmation: PASSWORD, confirmed_at: Time.current)
      user.skip_confirmation_notification!
      user.save!
    end
  end

  def self.organization(key)
    attributes = ORGANIZATIONS.fetch(key)
    owner_name, owner_email, = PEOPLE.fetch(key).first
    owner = user(owner_name, owner_email)

    Servora::Tenancy.with_context(organization_id: attributes[:id], user_id: owner.id) do
      organization = Organization.find_by(id: attributes[:id]) ||
                     Organization.create!(attributes.merge(onboarding_completed_at: Time.current))
      PEOPLE.fetch(key).each do |name, email, role, hourly_cost|
        person = user(name, email)
        organization.memberships.find_or_create_by!(user: person) do |membership|
          membership.role = role
          membership.hourly_cost = hourly_cost
        end
      end
      organization
    end
  end
end

Seeds.organization("a")
Seeds.organization("b")
puts "Organizações de demonstração prontas (senha local: #{Seeds::PASSWORD})."
