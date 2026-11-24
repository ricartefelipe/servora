# frozen_string_literal: true

# Working hours (Mon–Fri 08:00–12:00 and 13:00–18:00), skills and a team for
# the demonstration technicians.
module Seeds
  TECHNICIAN_SKILLS = {
    "diego@clima-norte.test" => ["Refrigeração comercial", "Elétrica"],
    "eduarda@clima-norte.test" => ["Refrigeração comercial"],
    "fabio@clima-norte.test" => ["Elétrica"],
    "julia@predial-sul.test" => ["Elevadores"]
  }.freeze
  SHIFTS = [[480, 720], [780, 1080]].freeze

  def self.technicians(key)
    organization_id = ORGANIZATIONS.fetch(key)[:id]
    Servora::Tenancy.with_organization(organization_id) do
      organization = Organization.find(organization_id)
      organization.memberships.technicians.includes(:user).find_each { |membership| seed_technician(organization, membership) }
      seed_team(organization) if key == "a"
    end
  end

  def self.seed_technician(organization, membership)
    if membership.work_schedules.none?
      (1..5).each do |weekday|
        SHIFTS.each do |start_minute, end_minute|
          WorkSchedule.create!(organization:, membership:, weekday:, start_minute:, end_minute:)
        end
      end
    end
    TECHNICIAN_SKILLS.fetch(membership.user.email, []).each do |name|
      skill = organization.skills.find_or_create_by!(name:)
      MembershipSkill.find_or_create_by!(organization:, membership:, skill:)
    end
  end

  def self.seed_team(organization)
    team = organization.teams.find_or_create_by!(name: "Equipe Refrigeração")
    organization.memberships.technicians.joins(:user)
      .where(users: { email: %w[diego@clima-norte.test eduarda@clima-norte.test] }).find_each do |membership|
      TeamMember.find_or_create_by!(organization:, team:, membership:)
    end
  end
end

Seeds.technicians("a")
Seeds.technicians("b")
puts "Técnicos com horários e competências prontos."
