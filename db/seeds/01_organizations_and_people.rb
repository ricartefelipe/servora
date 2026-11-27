# frozen_string_literal: true

# Demonstration organizations and people. Idempotent: organizations use fixed
# identifiers and people are looked up by e-mail. All addresses use the
# reserved ".test" domain; the shared password is for demonstration only.
#
# The password and the profiles offered on the sign-in page in demo mode come
# from Servora::Demo (config/initializers/servora_demo.rb): every listed account
# must be a person below with the same role, checked before anything is written.
require_relative "support/story_clock"
require_relative "support/organizations"

module Seeds
  PASSWORD = Servora::Demo.password

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

  def self.check_demo_accounts!
    seeded = PEOPLE.fetch("a").to_h { |_name, email, role, _cost| [email, role] }
    mismatched = Servora::Demo.accounts.reject { |account| seeded[account.email] == account.role }
    return if mismatched.empty?

    raise ArgumentError, "Servora::Demo accounts without a matching seeded person: #{mismatched.map(&:email).join(", ")}"
  end

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

Seeds.check_demo_accounts!
Seeds::StoryClock.at_origin do
  Seeds.organization("a")
  Seeds.organization("b")
end
puts "Organizações de demonstração prontas (senha das contas: #{Seeds::PASSWORD})."
