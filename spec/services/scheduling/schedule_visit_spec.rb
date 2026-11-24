# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scheduling::ScheduleVisit do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:work_order) { open_work_order(scenario) }
  let(:diego) { create_technician(organization, name: "Diego") }
  let(:eduarda) { create_technician(organization, name: "Eduarda") }

  it "reserves the technician, assigns the order and moves it to scheduled" do
    visit = schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(11), travel: 30)

    in_tenant(organization) do
      allocation = visit.allocations.sole
      expect(allocation.period).to eq(tuesday_at(9)...tuesday_at(11, 30))
      expect(work_order.reload.status).to eq("scheduled")
      expect(work_order.assignments.map(&:membership_id)).to eq([diego.id])
      expect(OutboxEvent.pluck(:event_type)).to include("visit.scheduled")
    end
  end

  it "rejects an overlapping reservation for the same technician, including the travel buffer" do
    schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10), travel: 30)
    other = open_work_order(scenario, title: "Outra")

    expect { schedule(scenario, other, [diego], from: tuesday_at(10, 15), to: tuesday_at(11)) }
      .to raise_error(described_class::Conflict, /Diego tem visita da #{work_order.number}/)
    expect(schedule(scenario, other, [diego], from: tuesday_at(10, 30), to: tuesday_at(11))).to be_persisted
  end

  it "reserves a whole team atomically: a conflict on one member leaves no partial reservation" do
    blocker = open_work_order(scenario, title: "Bloqueio")
    schedule(scenario, blocker, [eduarda], from: tuesday_at(14), to: tuesday_at(15))

    expect { schedule(scenario, work_order, [diego, eduarda], from: tuesday_at(14, 30), to: tuesday_at(16)) }
      .to raise_error(described_class::Conflict, /Eduarda/)

    in_tenant(organization) do
      expect(TechnicianAllocation.active.where(membership_id: diego.id)).to be_empty
      expect(work_order.reload.visits).to be_empty
      expect(work_order.status).to eq("approved")
    end
  end

  it "blocks visits during absences and absences over visits" do
    in_tenant(organization) do
      Scheduling::RegisterAbsence.new(membership: diego, starts_at: tuesday_at(8), ends_at: tuesday_at(12),
        reason: "Consulta médica", actor: scenario[:coordinator]).call
    end

    expect { schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10)) }
      .to raise_error(described_class::Conflict, /ausência \(Consulta médica\)/)
  end

  it "validates the period, working hours and technicians" do
    expect { schedule(scenario, work_order, [diego], from: tuesday_at(10), to: tuesday_at(9)) }
      .to raise_error(described_class::InvalidRequest, /término deve ser posterior/)
    expect { schedule(scenario, work_order, [diego], from: tuesday_at(11), to: tuesday_at(14)) }
      .to raise_error(described_class::InvalidRequest, /Fora do horário de trabalho de Diego/)
    expect { schedule(scenario, work_order, [], from: tuesday_at(9), to: tuesday_at(10)) }
      .to raise_error(described_class::InvalidRequest, /ao menos um técnico/)
  end

  it "does not schedule finished work orders" do
    as_member(scenario[:coordinator]) { WorkOrders::Cancel.new(work_order:, actor: scenario[:coordinator], reason: "Desistência").call }

    expect { schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10)) }
      .to raise_error(described_class::InvalidRequest, /não pode ser agendada/)
  end

  it "keeps the exclusion constraint even when bypassing the use case" do
    schedule(scenario, work_order, [diego], from: tuesday_at(9), to: tuesday_at(10))

    in_tenant(organization) do
      duplicate = TechnicianAllocation.new(organization:, membership: diego, kind: "absence", reason: "x",
        period: tuesday_at(9, 30)...tuesday_at(9, 45))
      expect { ActiveRecord::Base.transaction(requires_new: true) { duplicate.save! } }.to raise_error(ActiveRecord::ExclusionViolation)
    end
  end
end
