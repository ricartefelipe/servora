# frozen_string_literal: true

require_relative "history/restocking"

module Seeds
  module DemoActivity
    # Routine work of every business day of the story before today, on the
    # agenda of HistoryPlan: each visit requested by the customer (or opened
    # by the office for a preventive, or converted from a quote the customer
    # approved), scheduled, executed (checklist, report, materials, authorized
    # items, labor), completed, billed and paid — by Pix on the spot, by
    # transfer a few business days later or by boleto on its due date (still
    # open when that date has not come yet); homes mostly pay by Pix,
    # businesses by boleto or transfer. An installation registers the new
    # unit. The materials used are bought back every week, so the stock stays
    # close to its opening levels.
    #
    # The story class provides CUSTOMERS (with ClimaNortePool, the units the
    # work draws from, see RoutineJobs), HISTORY_SPECIALS (jobs done once, at
    # the first slot that suits them), HISTORY_QUOTES (approved quotes
    # executed by the team) and RESTOCKED (parts bought back every week).
    module History
      include RoutineJobs
      include HistoryPlan
      include Restocking

      # [method, due in (calendar days), paid after (business days; nil: on
      # the spot; :due on the due date)]
      PAYMENTS = {
        "individual" => [["pix", 0, nil], ["pix", 0, nil], ["transfer", 3, 1], ["pix", 0, nil], ["boleto", 7, :due]],
        "company" => [["boleto", 14, :due], ["transfer", 7, 3], ["pix", 0, nil], ["boleto", 10, :due], ["transfer", 5, 2],
                      ["boleto", 21, :due]]
      }.freeze
      ORIGINS = { "individual" => %w[whatsapp phone whatsapp], "company" => %w[email phone whatsapp email] }.freeze
      QUOTE_CHANNELS = %w[whatsapp email portal].freeze

      private

      def extra_events
        routines = history_plan
        [*routines.flat_map { |routine| routine_events(routine) }, *restocking(routines)]
      end

      def routine_events(routine)
        [*request(routine), *execution(routine), *closing(routine)]
      end

      # Opened (or converted from its quote) and scheduled shortly after; a
      # slow request is answered late in the afternoon (high priority: about
      # two and a half hours later; normal: after lunch, past four business
      # hours), after its first response deadline.
      def request(routine)
        day, opened = routine.requested
        scheduled = opened + (routine.slow ? slow_answer(routine) : 10) + (5 * hashed(routine.seed, "scheduled", 7))
        opening = routine.job[:kind] == :quote ? approved_quote(routine) : [[day, clock(opened), :open_order, opening(routine)]]
        [*opening,
         [day, clock(scheduled), :schedule, { by: :bruno, order: routine.key, on: routine.day, from: clock(routine.from),
                                              to: clock(routine.to), technicians: [routine.technician] }]]
      end

      def slow_answer(routine) = routine.priority == "high" ? 130 : 330

      def opening(routine)
        job = routine.job
        { by: :carla, key: routine.key, priority: routine.priority, origin: origin_of(routine), contact: job[:contact],
          service_type: service_type_name(job[:service_type]), **job.slice(:customer, :location, :equipment, :title, :problem) }
      end

      def origin_of(routine)
        return "preventive" if routine.job[:kind] == :preventive

        origins = ORIGINS.fetch(routine.job[:customer_kind])
        origins[hashed(routine.seed, "origin", origins.size)]
      end

      def service_type_name(kind)
        { corrective: self.class::CORRECTIVE, preventive: self.class::PREVENTIVE, installation: self.class::INSTALLATION }[kind]
      end

      # Drafted and sent four business days before it is approved by the
      # customer, then converted into the order.
      def approved_quote(routine)
        job = routine.job
        day, converted = routine.requested
        drafted = 540 + (5 * hashed(routine.seed, "drafted", 18))
        [[day - 4, clock(drafted), :quote, { by: :carla, key: routine.key, **job.slice(:customer, :location, :title),
                                             **job[:quote] }],
         [day - 4, clock(drafted + 20), :send_quote, { by: :carla, quote: routine.key }],
         [day, clock(converted - 40), :decide_quote, quote_decision(routine)],
         [day, clock(converted), :convert_quote, { by: :bruno, quote: routine.key, order: routine.key }]]
      end

      # Approved by the contact in the portal, or recorded by Carla from the
      # customer's e-mail or message.
      def quote_decision(routine)
        channel = QUOTE_CHANNELS[hashed(routine.seed, "channel", QUOTE_CHANNELS.size)]
        decision = { quote: routine.key, contact: routine.job[:contact], channel: }
        return decision if channel == "portal"

        { by: :carla, **decision, note: "Aprovado pelo cliente (#{channel == "email" ? "e-mail" : "mensagem"})." }
      end

      # Started on arrival; checklist, report, materials and items near the end.
      def execution(routine)
        job = routine.job
        finished = routine.to - hashed(routine.seed, "early", 6)
        items = job[:items] && visit_event(routine, finished - 6, :items, contact: job[:contact], channel: "in_person",
          lines: job[:items])
        [visit_event(routine, routine.from + hashed(routine.seed, "late", 6), :start),
         visit_event(routine, finished - 12, :report, job.slice(:diagnosis, :solution, :notes)),
         *consumptions(routine, finished - 10), *([items] if items),
         visit_event(routine, finished, :finish, outcome: job.fetch(:outcome, "Serviço concluído.")),
         *installation(routine, finished + 5)]
      end

      def consumptions(routine, minutes)
        routine.job.fetch(:materials, []).map do |sku, quantity|
          visit_event(routine, minutes, :consume, warehouse: self.class::CENTRAL, sku:, quantity:)
        end
      end

      # The unit installed by the visit, registered right after it.
      def installation(routine, minutes)
        row = routine.job[:install]
        row ? [[routine.day, clock(minutes), :register_equipment, { by: :bruno, customer: routine.job[:customer], row: }]] : []
      end

      # An event of the technician during the visit, `minutes` into the day.
      def visit_event(routine, minutes, action, params = {})
        [routine.day, clock(minutes), action, { by: routine.technician, order: routine.key, **params }]
      end

      def closing(routine)
        day, completed = closing_time(routine)
        billed = completed + 5 + (5 * hashed(routine.seed, "billed", 3))
        payments = PAYMENTS.fetch(routine.job[:customer_kind])
        method, due_in, paid_after = payments[routine.index % payments.size]
        [[day, clock(completed), :complete, { by: :bruno, order: routine.key }],
         [day, clock(billed), :bill, { by: :gabriela, order: routine.key, key: routine.key, due_in: }],
         [*payment_instant(day, billed, due_in, paid_after, routine.seed), :pay,
          { by: :gabriela, receivable: routine.key, method: }]]
      end

      # Completed right after the visit or, when the office is late, late
      # in the morning of the next business day (past the deadline).
      def closing_time(routine)
        return [routine.day + 1, 660 + (5 * hashed(routine.seed, "closed", 12))] if routine.late == :closing

        [routine.day, routine.to + 15 + (5 * hashed(routine.seed, "closed", 6))]
      end

      def payment_instant(day, billed, due_in, paid_after, seed)
        case paid_after
        when nil then [day, clock(billed + 10 + (5 * hashed(seed, "paid", 3)))]
        when :due then [settlement_day(calendar_day(day) + due_in), clock(560 + (5 * hashed(seed, "paid", 18)))]
        else [day + paid_after, clock(600 + (5 * hashed(seed, "paid", 48)))]
        end
      end
    end
  end
end
