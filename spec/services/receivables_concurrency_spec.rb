# frozen_string_literal: true

require "rails_helper"

# Two people register the remaining balance at the same moment: the row lock
# serializes them and the second one is refused instead of overpaying.
RSpec.describe Receivables, :committed do # concurrent payments
  it "accepts only one payment of the full balance" do
    scenario = build_work_order_scenario
    work_order = open_work_order(scenario)
    add_authorized_item(scenario, work_order, unit_price: "800")
    receivable = issue_receivable(scenario, work_order, "800")

    results = ConcurrencyHelpers.run_in_parallel(2) do
      pay(receivable, "800")
      :paid
    rescue Receivables::Errors::Invalid
      :refused
    end

    expect(results).to contain_exactly(:paid, :refused)
    expect(reload_in_tenant(receivable)).to have_attributes(paid_amount: 800, status: "paid")
  end
end
