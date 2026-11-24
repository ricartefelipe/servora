# frozen_string_literal: true

module Notifications
  # Pushes new notifications to the recipients' private streams. Each stream is
  # scoped to one membership and its subscription is authorized by
  # NotificationsChannel, so nothing is broadcast organization-wide.
  class BroadcastJob < ApplicationJob
    queue_as :default

    def perform(organization_id, notification_ids)
      deliveries = Servora::Tenancy.with_organization(organization_id) do
        Notification.where(id: notification_ids).includes(:recipient).map do |notification|
          [notification, Notification.for_recipient(notification.recipient).unread.count]
        end
      end
      deliveries.each { |notification, unread| broadcast(notification, unread) }
    end

    private

    def broadcast(notification, unread)
      Turbo::StreamsChannel.broadcast_prepend_to(
        notification.recipient, :notifications,
        target: "notifications-feed", partial: "notifications/notification", locals: { notification: }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        notification.recipient, :notifications,
        target: "notifications-counter", partial: "notifications/counter", locals: { unread: }
      )
    end
  end
end
