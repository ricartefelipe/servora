# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory do
  let(:scenario) { build_work_order_scenario }
  let(:organization) { scenario[:organization] }
  let(:coordinator) { scenario[:coordinator] }
  let(:central) { create(:warehouse, organization:, name: "Central") }
  let(:item) { stock_part(organization, name: "Capacitor 35 µF") }
  let!(:work_order) { open_work_order(scenario) }

  def reserve(quantity, order: work_order, warehouse: central)
    as_member(coordinator) do
      Inventory::Reserve.new(work_order: order, warehouse:, item:, quantity:, actor: coordinator).call
    end
  end

  def consume(quantity, reservation: nil, key: nil, warehouse: central)
    as_member(coordinator) do
      Inventory::Consume.new(work_order:, warehouse:, item:, quantity:, actor: coordinator, reservation:,
        idempotency_key: key).call
    end
  end

  describe Inventory::Receive do
    it "records the entry, recomputes the moving average and audits it" do
      receive_stock(central, item, "10", "12.00", actor: coordinator)
      movement = receive_stock(central, item, "5", "15.3333", actor: coordinator)

      expect(position(central, item)).to eq(["15.0", "0.0", "13.1111"])
      expect(movement).to have_attributes(kind: "entry", on_hand_after: 15, total_cost: BigDecimal("76.67"))
      expect(in_tenant(organization) { AuditEvent.where(action: "stock.received").count }).to eq(2)
    end

    it "replays a repeated submission instead of adding stock twice" do
      key = SecureRandom.uuid_v7
      first = receive_stock(central, item, "4", "10", key:)
      second = receive_stock(central, item, "4", "10", key:)

      expect(second).to eq(first)
      expect(position(central, item).first).to eq("4.0")
      expect { receive_stock(central, item, "9", "10", key:) }.to raise_error(Inventory::Errors::KeyReused)
    end

    it "refuses services, untracked parts and inactive warehouses" do
      service = create(:catalog_item, organization:)
      untracked = stock_part(organization, tracks_inventory: false)
      inactive = create(:warehouse, organization:, active: false)

      expect { receive_stock(central, service, "1", "1") }.to raise_error(Inventory::Errors::NotStockable)
      expect { receive_stock(central, untracked, "1", "1") }.to raise_error(Inventory::Errors::NotStockable)
      expect { receive_stock(inactive, item, "1", "1") }.to raise_error(Inventory::Errors::InvalidOperation, /inativo/)
      expect { receive_stock(central, item, "0", "1") }.to raise_error(Inventory::Errors::InvalidOperation)
    end
  end

  describe Inventory::Reserve do
    before { receive_stock(central, item, "5", "10") }

    it "moves quantity from available to reserved" do
      reservation = reserve("3")

      expect(position(central, item)).to eq(["5.0", "3.0", "10.0"])
      expect(reservation).to have_attributes(status: "active", remaining: 3)
      expect(balance_of(central, item).available).to eq(2)
    end

    it "rejects a reservation above the available quantity with a clear message" do
      reserve("3")

      expect { reserve("2.5") }.to raise_error(Inventory::Errors::Unavailable, /disponível 2, solicitado 2.5/)
      expect(position(central, item)).to eq(["5.0", "3.0", "10.0"])
    end

    it "refuses finished work orders" do
      as_member(coordinator) { WorkOrders::Cancel.new(work_order:, actor: coordinator, reason: "Cliente desistiu").call }

      expect { reserve("1") }.to raise_error(Inventory::Errors::InvalidOperation, /encerrada/)
    end
  end

  describe Inventory::Consume do
    before { receive_stock(central, item, "5", "10") }

    it "consumes from a reservation and closes it when nothing remains" do
      reservation = reserve("2")
      consume("2", reservation:)

      expect(position(central, item)).to eq(["3.0", "0.0", "10.0"])
      expect(in_tenant(organization) { reservation.reload.status }).to eq("closed")
    end

    it "consumes directly from the available quantity and keeps reserved stock untouched" do
      reserve("4")

      expect { consume("2") }.to raise_error(Inventory::Errors::Unavailable)
      consume("1")
      expect(position(central, item)).to eq(["4.0", "4.0", "10.0"])
    end

    it "keeps the historical cost even after more expensive purchases" do
      consumption = consume("2")
      receive_stock(central, item, "5", "30")

      expect(in_tenant(organization) { consumption.reload.unit_cost }).to eq(BigDecimal("10"))
      expect(consumption.total_cost).to eq(BigDecimal("20.00"))
      expect(position(central, item).last).to eq("22.5")
    end

    it "is idempotent with an operation key" do
      key = SecureRandom.uuid_v7
      first = consume("1", key:)

      expect(consume("1", key:)).to eq(first)
      expect(position(central, item).first).to eq("4.0")
    end

    it "rejects a reservation from another work order" do
      other = open_work_order(scenario, title: "Outra")
      foreign = reserve("1", order: other)

      expect { consume("1", reservation: foreign) }.to raise_error(Inventory::Errors::InvalidOperation, /não corresponde/)
    end

    it "never consumes more than the reservation still holds" do
      reservation = reserve("2")

      expect { consume("3", reservation:) }.to raise_error(Inventory::Errors::InvalidOperation, /saldo reservado/)
    end
  end

  describe Inventory::ReturnConsumption do
    it "returns unused material at the original cost and never above the consumed quantity" do
      receive_stock(central, item, "4", "10")
      consumption = consume("3")
      receive_stock(central, item, "1", "50")

      in_tenant(organization) do
        described_class.new(consumption:, quantity: "2", actor: coordinator).call
        expect(consumption.reload.net_quantity).to eq(1)
        expect(StockMovement.where(kind: "return").sole.unit_cost).to eq(BigDecimal("10"))
        expect { described_class.new(consumption:, quantity: "1.5", actor: coordinator).call }
          .to raise_error(Inventory::Errors::InvalidOperation, /supera o consumido/)
      end
    end
  end

  describe Inventory::ReleaseReservation do
    it "releases the remaining quantity once and ignores closed reservations" do
      receive_stock(central, item, "5", "10")
      reservation = reserve("3")
      consume("1", reservation:)

      in_tenant(organization) do
        2.times { described_class.new(reservation:, actor: coordinator).call }
        expect(reservation.reload).to have_attributes(status: "closed", released_quantity: 2, consumed_quantity: 1)
      end
      expect(position(central, item)).to eq(["4.0", "0.0", "10.0"])
    end

    it "is triggered by the work order cancellation through the outbox" do
      receive_stock(central, item, "5", "10")
      reserve("3")
      as_member(coordinator) { WorkOrders::Cancel.new(work_order:, actor: coordinator, reason: "Cliente desistiu").call }

      run_dispatcher

      expect(position(central, item)).to eq(["5.0", "0.0", "10.0"])
      expect(in_tenant(organization) { StockMovement.where(kind: "reservation_release").sole.reason })
        .to include("work_order.canceled")
    end
  end

  describe Inventory::Transfer do
    let(:van) { create(:warehouse, :vehicle, organization:, name: "Van 01") }

    it "moves stock at the source average cost in two linked movements" do
      receive_stock(central, item, "10", "10")
      receive_stock(van, item, "2", "16")

      outgoing = in_tenant(organization) do
        described_class.new(from: central, to: van, item:, quantity: "4", actor: coordinator, idempotency_key: "transfer-1").call
      end

      expect(position(central, item)).to eq(["6.0", "0.0", "10.0"])
      expect(position(van, item)).to eq(["6.0", "0.0", "12.0"])
      expect(in_tenant(organization) { StockMovement.where(transfer_group_id: outgoing.transfer_group_id).pluck(:kind) })
        .to contain_exactly("transfer_out", "transfer_in")
    end

    it "does nothing when the source lacks available stock or the warehouses are the same" do
      receive_stock(central, item, "1", "10")

      in_tenant(organization) do
        expect { described_class.new(from: central, to: van, item:, quantity: "2", actor: nil).call }
          .to raise_error(Inventory::Errors::Unavailable)
        expect { described_class.new(from: central, to: central, item:, quantity: "1", actor: nil).call }
          .to raise_error(Inventory::Errors::InvalidOperation, /diferentes/)
        expect(StockBalance.find_by(warehouse_id: van.id)&.on_hand.to_i).to eq(0)
      end
    end
  end

  describe Inventory::Adjust do
    before { receive_stock(central, item, "5", "10") }

    def adjust(quantity, reason: "Contagem física", unit_cost: nil)
      as_member(coordinator) do
        described_class.new(warehouse: central, item:, quantity:, actor: coordinator, reason:, unit_cost:).call
      end
    end

    it "adjusts in both directions with a mandatory reason and audit" do
      adjust("-2")
      adjust("1", unit_cost: "16")

      expect(position(central, item)).to eq(["4.0", "0.0", "11.5"])
      expect(in_tenant(organization) { AuditEvent.where(action: "stock.adjusted").count }).to eq(2)
      expect { adjust("1", reason: " ") }.to raise_error(Inventory::Errors::InvalidOperation, /motivo/)
      expect { adjust("0") }.to raise_error(Inventory::Errors::InvalidOperation, /zero/)
    end

    it "cannot remove reserved stock" do
      reserve("4")

      expect { adjust("-2") }.to raise_error(Inventory::Errors::Unavailable)
    end
  end

  describe Inventory::SetMinimum do
    it "flags positions below the threshold without touching quantities" do
      receive_stock(central, item, "3", "10")

      in_tenant(organization) do
        described_class.new(warehouse: central, item:, minimum: "4", actor: coordinator).call
        described_class.new(warehouse: central, item:, minimum: "4", actor: coordinator).call
        expect(StockBalance.below_minimum.pluck(:catalog_item_id)).to eq([item.id])
        expect(AuditEvent.where(action: "stock.minimum_changed").count).to eq(1)
        expect { described_class.new(warehouse: central, item:, minimum: "-1", actor: nil).call }
          .to raise_error(Inventory::Errors::InvalidOperation)
      end
      expect(position(central, item)).to eq(["3.0", "0.0", "10.0"])
    end
  end
end
