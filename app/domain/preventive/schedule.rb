# frozen_string_literal: true

module Preventive
  # Occurrence dates of a plan. Occurrence `anchor_sequence` falls on
  # `anchor_date`; occurrence n falls `n − anchor_sequence` periods later.
  # Re-anchoring (a schedule change) moves the anchor to the next sequence
  # without touching occurrences already generated.
  Schedule = Data.define(:anchor_date, :anchor_sequence, :frequency) do
    def due_on(sequence)
      raise ArgumentError, "sequence #{sequence} precedes the anchor" if sequence < anchor_sequence

      frequency.advance(anchor_date, sequence - anchor_sequence)
    end

    # Occurrences after `last_sequence` whose generation window has opened
    # (due date minus lead days not after `today`), oldest first and bounded,
    # so a scheduler that was down catches up gradually and in order.
    def pending(last_sequence:, today:, lead_days:, limit:, until_date: nil)
      sequence = [last_sequence + 1, anchor_sequence].max
      result = []
      while result.size < limit
        date = due_on(sequence)
        break if date - lead_days > today
        break if until_date && date > until_date

        result << [sequence, date]
        sequence += 1
      end
      result
    end

    def upcoming(from_sequence, count) = (0...count).map { |offset| [from_sequence + offset, due_on(from_sequence + offset)] }
  end
end
