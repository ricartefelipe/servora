# frozen_string_literal: true

require "rails_helper"

# Two dispatchers book the same technician for overlapping slots at the same
# time. Thread A inserts its reservation and keeps the transaction open; thread
# B tries to book and blocks inside PostgreSQL's exclusion check. Only after
# observing B waiting on a lock (pg_stat_activity) does A commit — no sleeps.
RSpec.describe Scheduling::ScheduleVisit, :committed do # concurrent booking of the same technician
  it "accepts one reservation and rejects the other" do # rubocop:disable RSpec/ExampleLength -- explicit thread choreography
    scenario = build_work_order_scenario
    organization = scenario[:organization]
    technician = create_technician(organization, name: "Fábio")
    first_order = open_work_order(scenario, title: "Primeira")
    second_order = open_work_order(scenario, title: "Segunda")
    a_inserted = Queue.new
    b_may_start = Queue.new
    a_may_commit = Queue.new

    thread_a = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        in_tenant(organization) do
          schedule(scenario, first_order, [technician], from: tuesday_at(9), to: tuesday_at(10))
          a_inserted << true
          a_may_commit.pop
        end
        :booked
      end
    end

    thread_b = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        b_may_start.pop
        schedule(scenario, second_order, [technician], from: tuesday_at(9, 30), to: tuesday_at(10, 30))
        :booked
      rescue Scheduling::ScheduleVisit::Conflict
        :rejected
      end
    end

    a_inserted.pop
    b_may_start << true
    ConcurrencyHelpers.wait_for_lock_wait
    a_may_commit << true

    expect([thread_a.value, thread_b.value]).to eq(%i[booked rejected])
    expect(in_tenant(organization) { TechnicianAllocation.active.where(membership_id: technician.id).count }).to eq(1)
  end
end
