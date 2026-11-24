# frozen_string_literal: true

module FinanceHelpers
  # Adds an item already authorized by the customer (as converted from a quote).
  def add_authorized_item(scenario, work_order, unit_price:, quantity: "1", unit_cost: nil, description: "Serviço contratado")
    in_tenant(scenario[:organization]) do
      line = Pricing::Line.build(quantity:, unit_price:, unit_cost:)
      WorkOrderItem.create!(organization_id: work_order.organization_id, work_order:, kind: "service", source: "quote",
        description:, unit: "un", quantity: line.quantity, unit_price: line.unit_price, unit_cost: line.unit_cost,
        line_total: line.total, authorization_status: "authorized", authorized_at: Time.current,
        authorized_by_membership_id: scenario[:coordinator].id)
    end
  end

  def issue_receivable(scenario, work_order, amount, due_on: Time.zone.today + 10)
    as_member(scenario[:coordinator]) do
      Receivables::Issue.new(work_order:, amount:, due_on:, actor: scenario[:coordinator]).call
    end
  end

  def pay(receivable, amount, key: nil, method: "pix")
    in_tenant(receivable.organization_id) do
      Receivables::RegisterPayment.new(receivable: receivable.reload, amount:, payment_method: method, actor: nil,
        idempotency_key: key).call
    end
  end

  def reload_in_tenant(record) = in_tenant(record.organization_id) { record.reload }
end

RSpec.configure do |config|
  config.include FinanceHelpers
end
