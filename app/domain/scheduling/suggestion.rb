# frozen_string_literal: true

module Scheduling
  # Deterministic ranking of technicians for a time slot. Candidates must hold
  # every required skill, be free in the blocked interval and work at that
  # time. Ties are broken by the least booked minutes that day, then by name
  # and id. This is a ranking heuristic, not route optimization.
  module Suggestion
    Candidate = Data.define(:id, :name, :skills, :available, :within_hours, :booked_minutes)

    module_function

    def rank(candidates, required_skills:)
      required = required_skills.to_set
      candidates
        .select { |c| c.available && c.within_hours && required.subset?(c.skills.to_set) }
        .sort_by { |c| [c.booked_minutes, c.name.to_s.downcase, c.id.to_s] }
    end

    # Why a candidate was not suggested (for the dispatcher's screen).
    def reasons(candidate, required_skills:)
      missing = required_skills.to_a - candidate.skills.to_a
      [
        ("Sem a competência: #{missing.join(", ")}" if missing.any?),
        ("Ocupado no horário" unless candidate.available),
        ("Fora do horário de trabalho" unless candidate.within_hours)
      ].compact
    end
  end
end
