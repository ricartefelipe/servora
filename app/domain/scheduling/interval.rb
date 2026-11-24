# frozen_string_literal: true

module Scheduling
  # Half-open time interval [starts_at, ends_at). The blocked interval of a
  # visit adds the travel buffer after the service: [start, end + travel).
  Interval = Data.define(:starts_at, :ends_at) do
    def initialize(starts_at:, ends_at:)
      raise ArgumentError, "start and end are required" if starts_at.nil? || ends_at.nil?
      raise ArgumentError, "start must be before end" unless starts_at < ends_at

      super
    end

    def self.for_visit(starts_at:, ends_at:, travel_minutes:)
      raise ArgumentError, "travel cannot be negative" if travel_minutes.to_i.negative?

      new(starts_at:, ends_at: ends_at + (travel_minutes.to_i * 60))
    end

    def overlaps?(other) = starts_at < other.ends_at && other.starts_at < ends_at
    def minutes = ((ends_at - starts_at) / 60).round
    def to_range = starts_at...ends_at
  end
end
