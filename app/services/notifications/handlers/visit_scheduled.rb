# frozen_string_literal: true

module Notifications
  module Handlers
    # visit.scheduled → notify each reserved technician.
    class VisitScheduled
      def call(event, context)
        visit = Visit.includes(:work_order, allocations: :membership).find(event.aggregate_id)
        technicians = visit.allocations.map(&:membership).select(&:active?)
        return if technicians.empty?

        Notifications::Deliver.new(event:, context:).call(
          recipients: technicians, kind: "visit.scheduled",
          title: "Nova visita: #{visit.work_order.number}",
          body: "#{visit.work_order.title} em #{I18n.l(visit.scheduled_start.in_time_zone, format: :short)}.",
          path: Rails.application.routes.url_helpers.work_order_path(visit.work_order)
        )
      end
    end
  end
end
