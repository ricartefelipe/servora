# frozen_string_literal: true

module Notifications
  module Handlers
    # sla.warning / sla.breached → notify who manages work orders and the
    # technicians assigned to it.
    class SlaAlert
      TITLES = { "sla.warning" => "Prazo em risco", "sla.breached" => "Prazo estourado" }.freeze

      def call(event, context)
        clock = SlaClock.find(event.aggregate_id)
        work_order = WorkOrder.includes(assignments: :membership).find(clock.work_order_id)
        recipients = (managers + work_order.assignments.map(&:membership)).select(&:active?).uniq
        return if recipients.empty?

        Notifications::Deliver.new(event:, context:).call(
          recipients:, kind: event.event_type, title: "#{TITLES.fetch(event.event_type)}: #{work_order.number}",
          body: body(clock, work_order), path: Rails.application.routes.url_helpers.work_order_path(work_order)
        )
      end

      private

      def body(clock, work_order)
        "#{clock.metric_label} de \"#{work_order.title}\" vence em #{I18n.l(clock.due_at.in_time_zone, format: :short)}."
      end

      def managers
        roles = Authorization::Permissions::ROLES.select { |role| Authorization::Permissions.granted?(role, :work_orders_manage) }
        Membership.active.where(role: roles).to_a
      end
    end
  end
end
