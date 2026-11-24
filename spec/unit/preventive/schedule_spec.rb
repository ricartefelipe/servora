# frozen_string_literal: true

RSpec.describe Preventive::Schedule do
  def schedule(anchor, unit: "month", interval: 1, anchor_sequence: 1)
    described_class.new(anchor_date: Date.iso8601(anchor), anchor_sequence:,
      frequency: Preventive::Frequency.new(unit:, interval:))
  end

  it "keeps month-end anchors instead of drifting" do
    dates = (1..5).map { |n| schedule("2026-01-31").due_on(n).iso8601 }

    expect(dates).to eq(%w[2026-01-31 2026-02-28 2026-03-31 2026-04-30 2026-05-31])
  end

  it "handles leap days on yearly and monthly plans" do
    yearly = schedule("2028-02-29", unit: "year")
    leap_month = schedule("2028-01-31")

    expect((1..5).map { |n| yearly.due_on(n).iso8601 }).to eq(%w[2028-02-29 2029-02-28 2030-02-28 2031-02-28 2032-02-29])
    expect(leap_month.due_on(2).iso8601).to eq("2028-02-29")
  end

  it "supports weekly and multi-period frequencies" do
    expect(schedule("2026-11-24", unit: "week", interval: 2).due_on(3).iso8601).to eq("2026-12-22")
    expect(schedule("2026-01-15", interval: 3).due_on(4).iso8601).to eq("2026-10-15")
  end

  it "lists pending occurrences within the lead window, in order and bounded" do
    plan = schedule("2026-01-10")

    expect(plan.pending(last_sequence: 0, today: Date.new(2026, 4, 3), lead_days: 7, limit: 12).map(&:first)).to eq([1, 2, 3, 4])
    expect(plan.pending(last_sequence: 0, today: Date.new(2026, 4, 3), lead_days: 7, limit: 2).map(&:first)).to eq([1, 2])
    expect(plan.pending(last_sequence: 4, today: Date.new(2026, 4, 3), lead_days: 7, limit: 12)).to eq([])
    expect(plan.pending(last_sequence: 0, today: Date.new(2026, 4, 3), lead_days: 0, limit: 12,
      until_date: Date.new(2026, 2, 28)).map(&:first)).to eq([1, 2])
  end

  it "continues from a new anchor after a schedule change" do
    plan = schedule("2026-06-01", anchor_sequence: 5, unit: "week")

    expect(plan.due_on(5).iso8601).to eq("2026-06-01")
    expect(plan.upcoming(5, 2).map { |_, date| date.iso8601 }).to eq(%w[2026-06-01 2026-06-08])
    expect { plan.due_on(4) }.to raise_error(ArgumentError)
  end

  it "validates the frequency and describes it" do
    expect { Preventive::Frequency.new(unit: "day", interval: 1) }.to raise_error(ArgumentError)
    expect { Preventive::Frequency.new(unit: "month", interval: 0) }.to raise_error(ArgumentError)
    expect(Preventive::Frequency.new(unit: "month", interval: 3).label).to eq("A cada 3 meses")
    expect(Preventive::Frequency.new(unit: "year", interval: 1).label).to eq("A cada ano")
  end
end
