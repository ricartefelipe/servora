# frozen_string_literal: true

module Notifications
  module Handlers
    # work_order.requested → notify who triages work orders.
    class PortalRequest
      def call(event, context)
        work_order = WorkOrder.includes(:customer).find(event.aggregate_id)
        roles = Authorization::Permissions::ROLES.select { |role| Authorization::Permissions.granted?(role, :work_orders_manage) }
        recipients = Membership.active.where(role: roles).to_a
        return if recipients.empty?

        Notifications::Deliver.new(event:, context:).call(
          recipients:, kind: "work_order.requested", title: "Novo chamado pelo portal: #{work_order.number}",
          body: "#{work_order.customer.display_name}: #{work_order.title}",
          path: Rails.application.routes.url_helpers.work_order_path(work_order)
        )
      end
    end
  end
end
