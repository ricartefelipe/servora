# frozen_string_literal: true

module TimeEntries
  # Records labor on a work order with the technician's hourly cost in force at
  # that moment (stored on the entry). With a client_operation_id the call is
  # idempotent: retries from the field app return the original entry.
  class Record
    class InvalidEntry < Servora::RuleViolation; end

    def initialize(work_order:, membership:, started_at:, ended_at:, source: "manual", visit: nil, notes: nil,
                   client_operation_id: nil)
      @work_order = work_order
      @membership = membership
      @started_at = started_at
      @ended_at = ended_at
      @source = source
      @visit = visit
      @notes = notes
      @client_operation_id = client_operation_id.presence
    end

    def call
      existing = @client_operation_id && TimeEntry.find_by(client_operation_id: @client_operation_id)
      return existing if existing

      raise InvalidEntry, "A ordem está encerrada." if @work_order.finished?

      interval = Scheduling::Interval.new(starts_at: @started_at, ends_at: @ended_at)
      @work_order.time_entries.create!(entry_attributes(interval))
    rescue ArgumentError
      raise InvalidEntry, "O término do apontamento deve ser posterior ao início."
    end

    private

    def entry_attributes(interval)
      hourly_cost = @membership.hourly_cost
      labor_cost = hourly_cost && Pricing::Amount.money(BigDecimal(interval.minutes) / 60 * hourly_cost)
      { organization_id: @work_order.organization_id, membership: @membership, visit: @visit, started_at: interval.starts_at,
        ended_at: interval.ends_at, minutes: interval.minutes, hourly_cost:, labor_cost:, source: @source, notes: @notes,
        client_operation_id: @client_operation_id }
    end
  end
end
