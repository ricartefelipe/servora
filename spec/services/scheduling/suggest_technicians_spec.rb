# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scheduling::SuggestTechnicians do
  it "suggests qualified free technicians, least booked first, and explains the others" do
    scenario = build_work_order_scenario
    organization = scenario[:organization]
    skill = in_tenant(organization) { Skill.create!(organization:, name: "Refrigeração comercial") }
    in_tenant(organization) { ServiceTypeSkill.create!(organization:, service_type: scenario[:service_type], skill:) }
    busy = create_technician(organization, name: "Bruno", skills: ["Refrigeração comercial"])
    loaded = create_technician(organization, name: "Ana", skills: ["Refrigeração comercial"])
    create_technician(organization, name: "Carla", skills: ["Refrigeração comercial"])
    create_technician(organization, name: "Davi")
    schedule(scenario, open_work_order(scenario, title: "A"), [busy], from: tuesday_at(9), to: tuesday_at(11))
    schedule(scenario, open_work_order(scenario, title: "B"), [loaded], from: tuesday_at(8), to: tuesday_at(8, 45), travel: 0)

    result = in_tenant(organization) do
      work_order = WorkOrder.includes(:organization, service_type: :skills).find(open_work_order(scenario).id)
      described_class.new(work_order:, starts_at: tuesday_at(10), ends_at: tuesday_at(11)).call
    end

    expect(result.ranked.map(&:name)).to eq(%w[Carla Ana])
    reasons = result.others.to_h { |candidate, why| [candidate.name, why] }
    expect(reasons["Bruno"]).to eq(["Ocupado no horário"])
    expect(reasons["Davi"]).to eq(["Sem a competência: Refrigeração comercial"])
  end
end
