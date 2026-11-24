# frozen_string_literal: true

RSpec.describe Sla::BusinessCalendar do
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:weekdays) { (1..5).index_with { [[480, 720], [780, 1080]] } } # 08–12, 13–18
  let(:calendar) { described_class.new(intervals: weekdays, holidays: [Date.new(2026, 11, 20)], zone:) }

  def at(text) = zone.parse(text)

  it "adds business time across lunch, evenings and weekends" do
    expect(calendar.add(at("2026-11-24 11:30"), 3600)).to eq(at("2026-11-24 13:30"))
    expect(calendar.add(at("2026-11-24 17:00"), 2 * 3600)).to eq(at("2026-11-25 09:00"))
    expect(calendar.add(at("2026-11-27 17:30"), 3600)).to eq(at("2026-11-30 08:30"))
  end

  it "starts counting at the next opening when created outside business hours" do
    expect(calendar.add(at("2026-11-24 06:00"), 1800)).to eq(at("2026-11-24 08:30"))
    expect(calendar.add(at("2026-11-28 10:00"), 1800)).to eq(at("2026-11-30 08:30"))
  end

  it "skips holidays" do
    expect(calendar.add(at("2026-11-19 17:00"), 2 * 3600)).to eq(at("2026-11-23 09:00"))
  end

  it "measures elapsed business time and returns zero for inverted ranges" do
    expect(calendar.elapsed(at("2026-11-24 11:00"), at("2026-11-24 14:00"))).to eq(2 * 3600)
    expect(calendar.elapsed(at("2026-11-27 17:00"), at("2026-11-30 09:00"))).to eq(2 * 3600)
    expect(calendar.elapsed(at("2026-11-24 14:00"), at("2026-11-24 11:00"))).to eq(0)
  end

  it "keeps add and elapsed consistent" do
    start = at("2026-11-24 15:47")
    due = calendar.add(start, (7 * 3600) + (13 * 60))

    expect(calendar.elapsed(start, due)).to eq((7 * 3600) + (13 * 60))
  end

  it "counts continuously when business hours are not required" do
    continuous = described_class.continuous(zone)

    expect(continuous.add(at("2026-11-28 22:00"), 4 * 3600)).to eq(at("2026-11-29 02:00"))
    expect(continuous.elapsed(at("2026-11-28 22:00"), at("2026-11-29 02:00"))).to eq(4 * 3600)
  end

  it "uses the organization's time zone" do
    manaus = described_class.new(intervals: weekdays, holidays: [], zone: "America/Manaus")

    expect(manaus.add(Time.utc(2026, 11, 24, 11, 0), 3600).utc).to eq(Time.utc(2026, 11, 24, 13, 0))
  end

  it "rejects calendars without business hours" do
    empty = described_class.new(intervals: {}, holidays: [], zone:)

    expect { empty.add(at("2026-11-24 10:00"), 60) }.to raise_error(ArgumentError, /no business hours/)
  end
end
