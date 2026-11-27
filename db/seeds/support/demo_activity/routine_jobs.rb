# frozen_string_literal: true

module Seeds
  module DemoActivity
    # The work the routine history draws from (History, HistoryPlan): for each
    # registered unit, the repairs its type can need, its preventive visits
    # (one order per site and interval, all the site's units of that
    # interval), and per customer a few visits without a unit. Homes get the
    # simpler repairs and smaller tickets (no extra labor hour); businesses
    # also the heavier ones.
    #
    # A job is a Hash with the work order data (customer, location,
    # equipment, service type, title, problem), what the visit records
    # (diagnosis, solution, notes, items, materials), who can do it (crew),
    # how long it takes (minutes) and its kind (:corrective, :preventive,
    # :misc) used by the rules of RoutineBook.
    module RoutineJobs
      private

      # Every job of the routine pool, built once per story run.
      def routine_pool
        @routine_pool ||= routine_customers.flat_map do |data|
          [*data[:equipment].flat_map { |row| unit_jobs(data, row) }, *preventive_jobs(data), *misc_jobs(data)]
        end
      end

      def routine_customers = Seeds::CUSTOMERS.fetch("a") + self.class::CUSTOMERS + ClimaNortePool::CUSTOMERS

      def unit_jobs(data, row)
        type, = row
        RoutineCatalog::CORRECTIVES.filter_map do |template|
          next unless template[:types].include?(type)
          next if template[:business] && data[:kind] == "individual"

          corrective_job(data, row, template)
        end
      end

      # Homes are not charged the extra labor hour. The unit takes one of the
      # template's wordings of the problem, and one diagnosis with its
      # solution (a unit never gets the same repair twice, see RoutineBook).
      def corrective_job(data, row, template)
        type, _, _, serial, location = row
        items = unit_lines(template[:items], row)
        items = items.reject { |line| line.first == "SRV-HORA" } if data[:kind] == "individual"
        { kind: :corrective, template: template[:key], customer: data[:document], location:, equipment: [serial],
          service_type: :corrective, crew: template[:crew], minutes: template[:minutes],
          title: format(template[:title], **unit_names(type, serial)), contact: data[:contacts].first[1],
          customer_kind: data[:kind], materials: unit_lines(template[:materials], row), items:,
          **unit_wording(template, serial) }
      end

      # { problem:, diagnosis:, solution: } of a unit's repair.
      def unit_wording(template, serial)
        seed = "#{serial}:#{template[:key]}"
        finding = hashed(seed, "finding", template[:diagnosis].size)
        { problem: wording(template[:problem], seed, "problem"), diagnosis: template[:diagnosis].fetch(finding),
          solution: template[:solution].fetch(finding) }
      end

      # One of the wordings of a text, the same on every load for `seed`.
      def wording(texts, seed, salt)
        texts = Array(texts)
        texts[hashed(seed, salt, texts.size)]
      end

      # { unit: "Split do quarto", of_unit: "do split do quarto" } for titles.
      def unit_names(type, serial)
        unit = "#{RoutineCatalog::SHORT.fetch(type)} #{ClimaNortePool::UNITS.fetch(serial).first}"
        { unit:, of_unit: "#{type == "Câmara fria" ? "da" : "do"} #{unit.sub(/\A\S+/, &:downcase)}" }
      end

      # Item or material lines with :gas and :charge resolved for the unit.
      def unit_lines(lines, (type, _, _, serial))
        gas = ClimaNortePool::UNITS.fetch(serial).last
        Array(lines).map do |sku, quantity|
          [sku == :gas ? gas : sku, quantity == :charge ? RoutineCatalog::CHARGE.fetch(type) : quantity]
        end
      end

      # One preventive job per site and interval, covering its units.
      def preventive_jobs(data)
        units = data[:equipment].filter_map do |type, _, _, serial, location|
          interval = ClimaNortePool::UNITS.fetch(serial)[1]
          interval && [location, interval, type, serial]
        end
        units.group_by { |location, interval, _, _| [location, interval] }.map do |(location, interval), group|
          preventive_job(data, location, interval, group.map { |_, _, type, serial| [type, serial] })
        end
      end

      def preventive_job(data, location, interval, units)
        count = units.size
        findings = RoutineCatalog::PREVENTIVE_FINDINGS
        diagnosis, notes = findings[hashed("#{data[:document]}:#{location}", "findings", findings.size)]
        items = [["SRV-PREV-SPLIT", count.to_s], *(count >= 3 ? [%w[SRV-HORA 1]] : [])]
        { kind: :preventive, interval:, customer: data[:document], location:, equipment: units.map(&:last),
          service_type: :preventive, crew: :all, minutes: 45 + (40 * count), title: preventive_title(interval, units, location),
          problem: RoutineCatalog::PREVENTIVE_REASONS.fetch(interval), diagnosis:, notes:, contact: data[:contacts].first[1],
          customer_kind: data[:kind], items:, materials: [],
          solution: wording(RoutineCatalog::PREVENTIVE_SOLUTIONS, "#{data[:document]}:#{location}:#{interval}", "solution") }
      end

      def preventive_title(interval, units, location)
        label = RoutineCatalog::INTERVAL_LABELS.fetch(interval)
        return "Preventiva #{label} do #{preventive_unit(units.first)}" if units.size == 1

        types = units.map(&:first).uniq
        noun = if types.all? { |type| type.start_with?("Split") } then "splits"
               elsif types == ["Cassete"] then "cassetes"
               else "equipamentos"
               end
        "Preventiva #{label} dos #{units.size} #{noun} — #{location}"
      end

      def preventive_unit((type, serial))
        "#{RoutineCatalog::SHORT.fetch(type).sub(/\A\S+/, &:downcase)} #{ClimaNortePool::UNITS.fetch(serial).first}"
      end

      # Only for the customers seen just in the history: the story's own
      # customers already have their visits without a unit (and the contracts
      # of two of them do not cover installations).
      def misc_jobs(data)
        return [] unless ClimaNortePool::CUSTOMERS.include?(data)

        RoutineCatalog::MISC.filter_map do |template|
          next unless template[:kinds].include?(data[:kind])

          { kind: :misc, template: template[:key], customer: data[:document], location: data[:locations].first.first,
            equipment: [], contact: data[:contacts].first[1], customer_kind: data[:kind],
            **template.slice(:service_type, :crew, :minutes, :title, :problem, :diagnosis, :solution, :items),
            materials: template.fetch(:materials, []) }
        end
      end
    end
  end
end
