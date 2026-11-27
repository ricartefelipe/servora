# frozen_string_literal: true

module Seeds
  module DemoActivity
    # What the routine history has already given each unit and customer, and
    # the rules a new order must follow (dates are request dates, as the
    # orders list and the equipment history show them):
    #
    # * a unit gets a repair at least CORRECTIVE_GAP days after (or before)
    #   another repair, and never the same repair twice in the story;
    # * a unit gets one preventive per interval (no two closer than the
    #   interval minus PREVENTIVE_SLACK days);
    # * a home has at most one order per unit plus one (three at most), at
    #   least HOME_GAP days apart;
    # * a business has its orders at least COMPANY_GAP days apart (never two
    #   requests of the same customer minutes apart) and, in any
    #   COMPANY_WINDOW days, at most its number of units plus COMPANY_EXTRA
    #   requests — plus QUIET_EXTRA more when the request fills a quiet day of
    #   the team (HistoryPlan::Choice). Preventives are not requests; the
    #   quotes it approved are agreed with it and are not limited, but count
    #   as requests for the later ones;
    # * a visit without a unit (MISC) happens once per customer.
    #
    # The hand-written orders of the story are reserved first, so the routine
    # work fits around them.
    class RoutineBook
      CORRECTIVE_GAP = 24
      INTERVAL_DAYS = { month: 30, quarter: 91, semester: 182 }.freeze
      PREVENTIVE_SLACK = 5
      HOME_GAP = 14
      COMPANY_GAP = 3
      COMPANY_EXTRA = 1
      QUIET_EXTRA = 1
      COMPANY_WINDOW = 30
      HOME_LIMIT = 3

      # customers: { document => [kind, number of units] }
      def initialize(customers)
        @customers = customers
        # serial => [request dates] of its repairs and preventives;
        # document => [request dates] of all its orders and of its requests.
        @correctives, @preventives, @orders, @requests = Array.new(4) { Hash.new { |hash, key| hash[key] = [] } }
        @repairs = Hash.new { |hash, serial| hash[serial] = Set.new }
        @misc = Set.new
      end

      # job: { kind:, customer:, equipment: [serials], template:, interval: },
      # or the same under :book (a quote whose order names no unit); agreed:
      # true for a quote the customer approved. quiet: the team has a quiet
      # day, and a business may get QUIET_EXTRA requests more than its usual
      # limit.
      def allows?(job, date, quiet: false)
        job = job.fetch(:book, job)
        customer_allows?(job, date, quiet) && unit_allows?(job, date)
      end

      def record(job, date)
        job = job.fetch(:book, job)
        @orders[job[:customer]] << date
        @requests[job[:customer]] << date unless job[:kind] == :preventive
        job[:equipment].each { |serial| record_unit(job, serial, date) }
        @misc << [job[:customer], job[:template]] if job[:kind] == :misc
      end

      def self.interval_days(interval) = INTERVAL_DAYS.fetch(interval || :month)

      private

      def record_unit(job, serial, date)
        case job[:kind]
        when :corrective
          @correctives[serial] << date
          @repairs[serial] << job[:template] if job[:template]
        when :preventive then @preventives[serial] << date
        end
      end

      def unit_allows?(job, date)
        case job[:kind]
        when :corrective then job[:equipment].all? { |serial| repair_allowed?(serial, job[:template], date) }
        when :preventive then job[:equipment].all? { |serial| preventive_allowed?(serial, job[:interval], date) }
        when :misc then @misc.exclude?([job[:customer], job[:template]])
        else true
        end
      end

      def repair_allowed?(serial, template, date)
        @correctives[serial].none? { |other| (other - date).abs < CORRECTIVE_GAP } && @repairs[serial].exclude?(template)
      end

      def preventive_allowed?(serial, interval, date)
        gap = self.class.interval_days(interval) - PREVENTIVE_SLACK
        @preventives[serial].none? { |other| (other - date).abs < gap }
      end

      def customer_allows?(job, date, quiet)
        kind, units = @customers.fetch(job[:customer])
        kind == "individual" ? home_allows?(job[:customer], units, date) : company_allows?(job, units, date, quiet)
      end

      def home_allows?(document, units, date)
        dates = @orders[document]
        dates.size < [units + 1, HOME_LIMIT].min && dates.none? { |other| (other - date).abs < HOME_GAP }
      end

      # A business's preventive visits and the quotes it approved (agreed:)
      # are agreed with it: they are not limited by its number of requests.
      def company_allows?(job, units, date, quiet)
        return false if @orders[job[:customer]].any? { |other| (other - date).abs < COMPANY_GAP }
        return true if job[:kind] == :preventive || job[:agreed]

        # Every request less than COMPANY_WINDOW days away shares some window
        # of that length with this one: keeping their count under the limit
        # keeps every window within it.
        recent = @requests[job[:customer]].count { |other| (other - date).abs < COMPANY_WINDOW }
        recent < units + COMPANY_EXTRA + (quiet ? QUIET_EXTRA : 0)
      end
    end
  end
end
