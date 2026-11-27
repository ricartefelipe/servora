# frozen_string_literal: true

module Seeds
  module DemoActivity
    module History
      # The materials used by the routine work are bought back every week
      # (History), so the stock stays close to its opening levels.
      module Restocking
        private

        # The week's materials (RESTOCKED parts), bought on its first business
        # day of the story before the first visit, at a cost close to the
        # catalog's.
        def restocking(routines)
          routines.group_by { |routine| calendar_day(routine.day).beginning_of_week }.flat_map do |week, group|
            day = group.min_by(&:day).day
            used_in(group).map do |sku, quantity|
              [day, "07:40", :restock, { by: :bruno, warehouse: self.class::CENTRAL, sku:, quantity: quantity.to_s("F"),
                                         factor: format("%.2f", 0.97 + (hashed("#{week}:#{sku}", "cost", 7) / 100.0)),
                                         reason: "Reposição semanal — NF #{4300 + (week.cweek * 7)}" }]
            end
          end
        end

        # { sku => quantity } of the RESTOCKED parts used by `routines`.
        def used_in(routines)
          materials = routines.flat_map { |routine| routine.job.fetch(:materials, []) }
          materials.each_with_object(Hash.new(BigDecimal("0"))) do |(sku, quantity), used|
            used[sku] += BigDecimal(quantity) if self.class::RESTOCKED.include?(sku)
          end
        end
      end
    end
  end
end
