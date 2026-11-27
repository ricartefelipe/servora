# frozen_string_literal: true

require "active_support/testing/time_helpers"

module Seeds
  # National holidays of 2026 and 2027, loaded by 08_sla.rb and used here to
  # count business days before the organizations' calendars exist. The story
  # keeps counting its days with this list (DemoActivity::Timeline), never
  # with the Holiday table, which visitors may change during the day.
  HOLIDAYS = {
    "2026-01-01" => "Confraternização Universal", "2026-04-03" => "Sexta-feira Santa", "2026-04-21" => "Tiradentes",
    "2026-05-01" => "Dia do Trabalho", "2026-09-07" => "Independência do Brasil", "2026-10-12" => "Nossa Senhora Aparecida",
    "2026-11-02" => "Finados", "2026-11-15" => "Proclamação da República", "2026-11-20" => "Dia da Consciência Negra",
    "2026-12-25" => "Natal", "2027-01-01" => "Confraternização Universal", "2027-03-26" => "Sexta-feira Santa",
    "2027-04-21" => "Tiradentes", "2027-05-01" => "Dia do Trabalho", "2027-09-07" => "Independência do Brasil",
    "2027-10-12" => "Nossa Senhora Aparecida", "2027-11-02" => "Finados", "2027-11-15" => "Proclamação da República",
    "2027-11-20" => "Dia da Consciência Negra", "2027-12-25" => "Natal"
  }.freeze

  # Business hours loaded by 08_sla.rb (Monday to Friday, minutes of the day).
  SHIFTS_SLA = [[480, 720], [780, 1080]].freeze

  # Clock of the demonstration story (db/seeds/10_demo_activity.rb).
  #
  # The story covers HISTORY_DAYS business days before today. When it is
  # enabled, the base seeds that write history (organizations, people,
  # equipment, catalog, opening stock, contract, SLA) run with the clock at the
  # origin of the story, 08:00 of the business day before its first day, so
  # every ledger, audit trail and timestamp reads in chronological order. Dates
  # that must stay relative to the real day (warranties, the next preventive
  # occurrence) use StoryClock.today, which is the run date even at the origin.
  module StoryClock
    extend ActiveSupport::Testing::TimeHelpers

    HISTORY_DAYS = 30

    module_function

    def enabled? = ENV.fetch("SEED_DEMO_ACTIVITY", Rails.env.development? ? "1" : "0") == "1"

    # Business days of history before today (the specs may shorten it).
    def history_days = HISTORY_DAYS

    # Both demonstration organizations use the application time zone.
    def zone = Time.zone

    # The run instant, also while the clock is at the origin.
    def now = @run_at || Time.current
    def today = now.in_time_zone(zone).to_date

    def origin(from: now)
      date = business_day(-(history_days + 2), from: from.in_time_zone(zone).to_date)
      zone.local(date.year, date.month, date.day, 8)
    end

    # n business days from `from` (Monday to Friday, national holidays excluded).
    def business_day(offset, from: today)
      step = offset.negative? ? -1 : 1
      date = from
      offset.abs.times do
        date += step
        date += step until business_day?(date)
      end
      date
    end

    def business_day?(date) = date.on_weekday? && !HOLIDAYS.key?(date.iso8601)

    # Runs a base seed at the origin of the story (or now, when disabled).
    def at_origin(&)
      return yield unless enabled?

      @run_at = Time.current
      travel_to(origin, &)
    ensure
      @run_at = nil
    end
  end
end
