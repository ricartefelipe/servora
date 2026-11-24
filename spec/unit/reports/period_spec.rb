# frozen_string_literal: true

RSpec.describe Reports::Period do
  let(:today) { Date.new(2026, 11, 24) }

  it "defaults to the current month and accepts explicit dates" do
    expect(described_class.parse(from: nil, to: nil, today:)).to have_attributes(from: Date.new(2026, 11, 1), to: today)
    expect(described_class.parse(from: "2026-10-01", to: "2026-10-31", today:).days).to eq(31)
  end

  it "ignores invalid input, swaps inverted ranges and limits the length" do
    expect(described_class.parse(from: "ontem", to: "2026-13-40", today:).from).to eq(Date.new(2026, 11, 1))
    expect(described_class.parse(from: "2026-11-10", to: "2026-11-01",
      today:).to_param).to eq(de: "2026-11-01", ate: "2026-11-10")
    expect(described_class.parse(from: "2020-01-01", to: "2026-11-24", today:).days).to eq(366)
  end

  it "covers whole days in the organization's time zone" do
    period = described_class.parse(from: "2026-11-01", to: "2026-11-30", today:)
    range = period.range(ActiveSupport::TimeZone["America/Sao_Paulo"])

    expect([range.begin.utc.iso8601, range.end.utc.iso8601,
            range.exclude_end?]).to eq(["2026-11-01T03:00:00Z", "2026-12-01T03:00:00Z", true])
    expect(period.label).to eq("01/11/2026 a 30/11/2026")
  end
end
