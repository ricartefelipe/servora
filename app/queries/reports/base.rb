# frozen_string_literal: true

module Reports
  # Common shape of a management report: headline figures (summary), a table
  # (headers + rows) shown on screen and exported as CSV. Every query runs in
  # the request's tenant context and aggregates in the database.
  class Base
    SCREEN_ROWS = 200
    EXPORT_ROWS = 10_000

    attr_reader :period

    def initialize(period:, zone:, show_costs:)
      @period = period
      @zone = zone
      @show_costs = show_costs
    end

    def title = raise(NotImplementedError)
    def summary = raise(NotImplementedError)
    def headers = raise(NotImplementedError)
    def rows(limit:) = raise(NotImplementedError)

    private

    def range = @period.range(@zone)
    def money(value) = Money.of(value)
    def hours(minutes) = (BigDecimal(minutes.to_i) / 60).round(1)
    def local(time) = time&.in_time_zone(@zone)&.strftime("%d/%m/%Y %H:%M")
  end
end
