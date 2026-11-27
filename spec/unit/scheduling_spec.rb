# frozen_string_literal: true

RSpec.describe Scheduling do
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }

  describe Scheduling::Interval do
    it "uses half-open semantics: back-to-back intervals do not overlap" do
      morning = described_class.new(starts_at: zone.parse("2026-11-24 08:00"), ends_at: zone.parse("2026-11-24 10:00"))
      next_one = described_class.new(starts_at: zone.parse("2026-11-24 10:00"), ends_at: zone.parse("2026-11-24 11:00"))
      overlapping = described_class.new(starts_at: zone.parse("2026-11-24 09:59"), ends_at: zone.parse("2026-11-24 11:00"))

      expect(morning.overlaps?(next_one)).to be(false)
      expect(morning.overlaps?(overlapping)).to be(true)
      expect(morning.minutes).to eq(120)
    end

    it "adds the travel buffer after the visit" do
      blocked = described_class.for_visit(starts_at: zone.parse("2026-11-24 08:00"), ends_at: zone.parse("2026-11-24 09:00"),
        travel_minutes: 30)

      expect(blocked.ends_at).to eq(zone.parse("2026-11-24 09:30"))
      expect(blocked.to_range).to eq(blocked.starts_at...blocked.ends_at)
    end

    it "rejects empty, inverted or incomplete intervals" do
      now = zone.parse("2026-11-24 08:00")

      expect { described_class.new(starts_at: now, ends_at: now) }.to raise_error(ArgumentError, /before/)
      expect { described_class.new(starts_at: now, ends_at: nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.for_visit(starts_at: now, ends_at: now + 3600, travel_minutes: -5) }.to raise_error(ArgumentError)
    end
  end

  describe Scheduling::WorkingHours do
    let(:hours) do
      described_class.new([described_class::Slot.new(2, 480, 720), described_class::Slot.new(2, 780, 1080)])
    end

    it "accepts periods inside a shift of the same weekday" do
      expect(hours.fits?(zone.parse("2026-11-24 08:00"), zone.parse("2026-11-24 12:00"))).to be(true)
      expect(hours.fits?(zone.parse("2026-11-24 13:00"), zone.parse("2026-11-24 15:30"))).to be(true)
    end

    it "rejects periods across the lunch break, other weekdays or midnight" do
      expect(hours.fits?(zone.parse("2026-11-24 11:00"), zone.parse("2026-11-24 14:00"))).to be(false)
      expect(hours.fits?(zone.parse("2026-11-25 09:00"), zone.parse("2026-11-25 10:00"))).to be(false)
      expect(hours.fits?(zone.parse("2026-11-24 23:00"), zone.parse("2026-11-25 01:00"))).to be(false)
      expect(described_class.new([described_class::Slot.new(2, 1320, 1440)])
        .fits?(zone.parse("2026-11-24 22:00"), zone.parse("2026-11-25 00:00"))).to be(true)
    end

    it "lists the shifts of a weekday in order" do
      expect(hours.for_weekday(2).map(&:start_minute)).to eq([480, 780])
      expect(described_class.new([])).to be_empty
    end
  end

  describe Scheduling::Suggestion do
    let(:candidate) { described_class::Candidate }
    let(:candidates) do
      [candidate.new("3", "Carla", %w[refrigeracao], true, true, 120),
       candidate.new("1", "Bruno", %w[refrigeracao eletrica], true, true, 60),
       candidate.new("2", "Ana", %w[refrigeracao eletrica], true, true, 60),
       candidate.new("4", "Davi", %w[refrigeracao eletrica], false, true, 0),
       candidate.new("5", "Eva", %w[refrigeracao eletrica], true, false, 0)]
    end

    it "keeps only qualified, free technicians within working hours, least booked first, deterministically" do
      ranked = described_class.rank(candidates, required_skills: %w[eletrica refrigeracao])

      expect(ranked.map(&:name)).to eq(%w[Ana Bruno])
      expect(described_class.rank(candidates.reverse,
        required_skills: %w[eletrica refrigeracao]).map(&:name)).to eq(%w[Ana Bruno])
    end

    it "explains why a technician was not suggested" do
      expect(described_class.reasons(candidates[0], required_skills: %w[eletrica])).to eq(["Sem a competência: eletrica"])
      expect(described_class.reasons(candidates[3], required_skills: [])).to eq(["Ocupado no horário"])
      expect(described_class.reasons(candidates[4], required_skills: [])).to eq(["Fora do horário de trabalho"])
    end
  end

  describe Scheduling::DefaultStart do
    def proposal(now, **calendar) = described_class.new(now: zone.parse(now), **calendar).call

    it "proposes 09:00 on the next weekday when no opening hours are configured" do
      expect(proposal("2026-11-24 16:00")).to eq(zone.parse("2026-11-25 09:00")) # Tuesday → Wednesday
      expect(proposal("2026-11-27 10:00")).to eq(zone.parse("2026-11-30 09:00")) # Friday → Monday
      expect(proposal("2026-11-28 10:00")).to eq(zone.parse("2026-11-30 09:00")) # Saturday → Monday
    end

    it "skips holidays and the days the office is closed" do
      saturday_morning = { 1 => [[480, 1080]], 2 => [[480, 1080]], 6 => [[480, 720]] }

      expect(proposal("2026-11-27 10:00", opening_hours: saturday_morning)).to eq(zone.parse("2026-11-28 09:00"))
      expect(proposal("2026-11-27 10:00", opening_hours: saturday_morning, holidays: [Date.new(2026, 11, 28)]))
        .to eq(zone.parse("2026-11-30 09:00"))
      expect(proposal("2026-11-27 10:00", holidays: [Date.new(2026, 11, 30)])).to eq(zone.parse("2026-12-01 09:00"))
    end

    it "moves to the opening when the office is not open at 09:00" do
      expect(proposal("2026-11-24 10:00", opening_hours: { 3 => [[600, 1080]] })).to eq(zone.parse("2026-11-25 10:00"))
      expect(proposal("2026-11-24 10:00", opening_hours: { 3 => [[420, 510], [780, 1080]] }))
        .to eq(zone.parse("2026-11-25 13:00"))
      expect(proposal("2026-11-24 10:00", opening_hours: { 3 => [[360, 480]] })).to eq(zone.parse("2026-11-25 06:00"))
    end
  end

  describe Visits::States do
    it "never completes a visit without starting it" do
      expect(described_class.allowed?(:scheduled, :completed)).to be(false)
      expect(described_class.allowed?(:in_progress, :completed)).to be(true)
      expect(Visits::LABELS.keys).to match_array(described_class.states)
    end

    it "puts the trip between scheduled and in progress without making it mandatory" do
      expect(described_class.targets(:scheduled)).to eq(%w[traveling in_progress canceled no_show])
      expect(described_class.targets(:traveling)).to eq(%w[in_progress canceled no_show])
      expect(Visits::LABELS.fetch("traveling")).to eq("Em deslocamento")
    end

    it "never takes a visit on the way back to scheduled nor ends it without starting" do
      expect(described_class.allowed?(:traveling, :scheduled)).to be(false)
      expect(described_class.allowed?(:traveling, :completed)).to be(false)
      expect(described_class.allowed?(:in_progress, :traveling)).to be(false)
    end

    it "gives every state a tone and counts the trip as time in the field" do
      expect(Visits::TONES.keys).to match_array(described_class.states)
      expect(Visits::TONES.values_at("traveling", "in_progress")).to eq(%i[ember ember])
      expect(Visits::IN_FIELD).to contain_exactly("traveling", "in_progress")
      expect(Visits::OPEN).to contain_exactly("scheduled", "traveling", "in_progress")
      expect(Visits::OPEN.reject { |state| described_class.terminal?(state) }).to eq(Visits::OPEN)
    end
  end
end
