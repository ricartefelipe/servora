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

  describe Visits::States do
    it "never completes a visit without starting it" do
      expect(described_class.allowed?(:scheduled, :completed)).to be(false)
      expect(described_class.allowed?(:in_progress, :completed)).to be(true)
      expect(Visits::LABELS.keys).to match_array(described_class.states)
    end
  end
end
