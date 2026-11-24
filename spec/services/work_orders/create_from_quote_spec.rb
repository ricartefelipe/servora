# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkOrders::CreateFromQuote do
  def approved_quote(scenario)
    quote = create_quote(scenario, items: [["Manutenção preventiva", "2", "180.00"]])
    version = send_quote(scenario, quote)
    in_tenant(scenario[:organization]) do
      Quotes::Decide.new(quote: quote.reload, version_id: version.id, decision: "approved", digest: version.content_digest,
        contact: scenario[:approver], channel: "portal").call
      quote.reload
    end
  end

  context "with a single request" do
    let(:scenario) { build_quote_scenario }

    it "creates the work order once with authorized items from the approved version" do
      quote = approved_quote(scenario)

      first = in_tenant(scenario[:organization]) { described_class.new(quote:, actor: scenario[:author]).call }
      second = in_tenant(scenario[:organization]) { described_class.new(quote: quote.reload, actor: scenario[:author]).call }

      expect([first.created, second.created]).to eq([true, false])
      expect(second.work_order.id).to eq(first.work_order.id)
      in_tenant(scenario[:organization]) do
        expect(first.work_order.items.map { |i| [i.description, i.authorization_status, i.line_total] })
          .to eq([["Manutenção preventiva", "authorized", BigDecimal("360.00")]])
        expect(quote.reload.status).to eq("converted")
      end
    end

    it "refuses quotes that are not approved" do
      quote = create_quote(scenario)

      expect { in_tenant(scenario[:organization]) { described_class.new(quote:, actor: scenario[:author]).call } }
        .to raise_error(described_class::NotConvertible)
    end
  end

  context "with concurrent requests", :committed do
    it "creates exactly one work order when two conversions race" do
      scenario = build_quote_scenario
      quote = approved_quote(scenario)

      results = ConcurrencyHelpers.run_in_parallel(2) do
        in_tenant(scenario[:organization]) { described_class.new(quote: Quote.find(quote.id), actor: scenario[:author]).call }
      end

      expect(results.map(&:created).sort_by { |created| created ? 0 : 1 }).to eq([true, false])
      expect(results.map { |r| r.work_order.id }.uniq.size).to eq(1)
      expect(in_tenant(scenario[:organization]) { WorkOrder.count }).to eq(1)
    end
  end
end
