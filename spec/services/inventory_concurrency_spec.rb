# frozen_string_literal: true

require "rails_helper"

# Real concurrency: each thread has its own connection and commits. Ordering
# is decided by PostgreSQL row locks; synchronization uses queues and
# pg_stat_activity, never sleeps.
RSpec.describe Inventory, :committed do # concurrent stock operations
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let(:central) { create(:warehouse, organization:, name: "Central") }
  let(:item) { stock_part(organization, name: "Compressor rotativo") }

  def reserve(order)
    as_member(coordinator) do
      Inventory::Reserve.new(work_order: order, warehouse: central, item:, quantity: "1", actor: coordinator).call
    end
    :reserved
  rescue Inventory::Errors::Unavailable
    :unavailable
  end

  it "gives the last unit to exactly one of two competing work orders" do
    first_order = open_work_order(scenario, title: "Primeira")
    second_order = open_work_order(scenario, title: "Segunda")
    receive_stock(central, item, "1", "300")
    a_locked = Queue.new
    a_may_commit = Queue.new

    thread_a = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        as_member(coordinator) do
          Inventory::Reserve.new(work_order: first_order, warehouse: central, item:, quantity: "1", actor: coordinator).call
          a_locked << true
          a_may_commit.pop
        end
        :reserved
      end
    end
    a_locked.pop
    thread_b = Thread.new { ActiveRecord::Base.connection_pool.with_connection { reserve(second_order) } }
    ConcurrencyHelpers.wait_for_lock_wait
    a_may_commit << true

    expect([thread_a.value, thread_b.value]).to eq(%i[reserved unavailable])
    expect(position(central, item)).to eq(["1.0", "1.0", "300.0"])
    expect(in_tenant(organization) { StockReservation.count }).to eq(1)
  end

  it "runs opposite transfers at the same time without deadlock and conserves stock" do
    van = create(:warehouse, :vehicle, organization:, name: "Van 02")
    receive_stock(central, item, "10", "10")
    receive_stock(van, item, "10", "10")
    # Two transfers in each direction (the test pool has five connections).
    routes = [[central, van], [van, central]] * 2

    results = ConcurrencyHelpers.run_in_parallel(routes.size) do |index|
      from, to = routes[index]
      in_tenant(organization) { Inventory::Transfer.new(from:, to:, item:, quantity: "1", actor: nil).call }
      :done
    end

    expect(results).to all(eq(:done))
    expect([position(central, item).first, position(van, item).first]).to eq(["10.0", "10.0"])
    expect(in_tenant(organization) { StockMovement.where(kind: %w[transfer_out transfer_in]).count }).to eq(8)
  end

  it "records a consumption once when the same operation arrives twice concurrently" do
    work_order = open_work_order(scenario)
    receive_stock(central, item, "5", "10")
    key = SecureRandom.uuid_v7

    ids = ConcurrencyHelpers.run_in_parallel(2) do
      as_member(coordinator) do
        Inventory::Consume.new(work_order:, warehouse: central, item:, quantity: "2", actor: coordinator,
          idempotency_key: key).call.id
      end
    end

    expect(ids.uniq.size).to eq(1)
    expect(position(central, item).first).to eq("3.0")
    expect(in_tenant(organization) { MaterialConsumption.count }).to eq(1)
  end
end
