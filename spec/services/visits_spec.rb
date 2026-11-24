# frozen_string_literal: true

require "rails_helper"

RSpec.describe Visits do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:work_order) { open_work_order(scenario) }
  let(:technician) { create_technician(organization, name: "Diego") }
  let!(:visit) { schedule(scenario, work_order, [technician], from: tuesday_at(9), to: tuesday_at(12), travel: 30) }

  def reload(record) = in_tenant(organization) { record.reload }

  it "starts the work order with the first visit and never completes it by finishing the visit" do
    in_tenant(organization) { Visits::Start.new(visit:, actor: technician, at: tuesday_at(9, 5)).call }
    in_tenant(organization) do
      Visits::Finish.new(visit: visit.reload, actor: technician, outcome_note: "Falta peça", needs_return: true,
        at: tuesday_at(10)).call
    end

    expect(reload(work_order)).to have_attributes(status: "in_progress", started_at: tuesday_at(9, 5))
    expect(reload(visit)).to have_attributes(status: "completed", needs_return: true)
    expect(in_tenant(organization) { visit.allocations.sole.period }).to eq(tuesday_at(9)...tuesday_at(10, 30))
  end

  it "frees the technician earlier when a visit ends ahead of time" do
    in_tenant(organization) do
      Visits::Start.new(visit:, actor: technician, at: tuesday_at(9)).call
      Visits::Finish.new(visit: visit.reload, actor: technician, at: tuesday_at(9, 45)).call
    end

    other = open_work_order(scenario, title: "Encaixe")
    expect(schedule(scenario, other, [technician], from: tuesday_at(10, 15), to: tuesday_at(11))).to be_persisted
  end

  it "rejects invalid visit transitions" do
    expect { in_tenant(organization) { Visits::Finish.new(visit:, actor: technician).call } }
      .to raise_error(Visits::Transition::InvalidTransition, /agendada/)
  end

  it "cancels, releases the technician and returns the order to approved" do
    in_tenant(organization) { Visits::Cancel.new(visit:, actor: scenario[:coordinator], reason: "Cliente pediu outra data").call }

    in_tenant(organization) do
      expect(visit.reload.status).to eq("canceled")
      expect(visit.allocations.active).to be_empty
      expect(work_order.reload.status).to eq("approved")
    end
  end

  it "records a customer no-show and puts the order waiting for the customer" do
    in_tenant(organization) { Visits::Cancel.new(visit:, actor: scenario[:coordinator], reason: "Portaria fechada", no_show: true).call }

    expect(reload(work_order).status).to eq("waiting_customer")
    expect { in_tenant(organization) { Visits::Cancel.new(visit: visit.reload, actor: nil, reason: "").call } }
      .to raise_error(Visits::Cancel::ReasonRequired)
  end

  it "reschedules keeping the original reservation when the new slot conflicts" do
    blocker = open_work_order(scenario, title: "Outra")
    schedule(scenario, blocker, [technician], from: tuesday_at(14), to: tuesday_at(15))

    expect do
      in_tenant(organization) do
        Scheduling::RescheduleVisit.new(visit:, starts_at: tuesday_at(14, 30), ends_at: tuesday_at(15, 30),
          actor: scenario[:coordinator]).call
      end
    end.to raise_error(Scheduling::ScheduleVisit::Conflict)
    expect(in_tenant(organization) { visit.allocations.active.sole.period.begin }).to eq(tuesday_at(9))

    in_tenant(organization) do
      Scheduling::RescheduleVisit.new(visit: visit.reload, starts_at: tuesday_at(15, 30), ends_at: tuesday_at(17),
        actor: scenario[:coordinator], reason: "Pedido do cliente").call
    end
    in_tenant(organization) do
      expect(visit.reload.scheduled_start).to eq(tuesday_at(15, 30))
      expect(visit.allocations.active.sole.period).to eq(tuesday_at(15, 30)...tuesday_at(17, 30))
      expect(visit.transitions.first.reason).to include("Reagendada", "Pedido do cliente")
    end
  end

  it "cancels upcoming visits when the work order is canceled (outbox handler)" do
    visit
    as_member(scenario[:coordinator]) { WorkOrders::Cancel.new(work_order: work_order.reload, actor: scenario[:coordinator], reason: "Desistiu").call }

    run_dispatcher

    expect(reload(visit).status).to eq("canceled")
    expect(in_tenant(organization) { TechnicianAllocation.active.count }).to eq(0)
  end

  it "blocks completion of the work order while a visit is in progress" do
    in_tenant(organization) { Visits::Start.new(visit:, actor: technician).call }
    in_tenant(organization) do
      work_order.reload.update!(diagnosis: "Ok", solution: "Ok")
      work_order.checklist_items.each { |item| item.update!(response: item.response_kind == "number" ? "1" : "sim") }
    end

    complete = -> { WorkOrders::Complete.new(work_order: work_order.reload, actor: scenario[:coordinator]).call }

    expect { as_member(scenario[:coordinator], &complete) }
      .to raise_error(WorkOrders::Complete::RequirementsMissing, /visita em andamento/)
  end
end
