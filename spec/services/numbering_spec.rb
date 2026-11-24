# frozen_string_literal: true

require "rails_helper"

RSpec.describe Numbering, :committed do
  it "allocates unique sequential numbers under concurrency" do
    organization = create(:organization, time_zone: "America/Sao_Paulo")

    numbers = ConcurrencyHelpers.run_in_parallel(4) do
      Array.new(5) do
        in_tenant(organization) do
          described_class.next!(organization:, scope: "quote", at: Time.zone.parse("2026-11-24 10:00"))
        end
      end
    end.flatten

    expect(numbers.uniq.size).to eq(20)
    expect(numbers.min).to eq("ORC-2026-00001")
    expect(numbers.max).to eq("ORC-2026-00020")
  end

  it "restarts the sequence per year in the organization time zone" do
    organization = create(:organization, time_zone: "America/Sao_Paulo")

    late_in_year = in_tenant(organization) { described_class.next!(organization:, scope: "quote", at: Time.utc(2027, 1, 1, 2)) }
    early_next_year = in_tenant(organization) do
      described_class.next!(organization:, scope: "quote", at: Time.utc(2027, 1, 1, 4))
    end

    expect([late_in_year, early_next_year]).to eq(%w[ORC-2026-00001 ORC-2027-00001])
  end
end
