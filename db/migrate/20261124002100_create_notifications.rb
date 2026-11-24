# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  def change
    create_tenant_table :notifications do |t|
      t.string :kind, null: false
      t.string :title, null: false
      t.string :body
      t.string :path
      t.datetime :read_at
      # Identifier of the originating event, used only for deduplication (no FK:
      # processed outbox events may be purged by retention without touching inboxes).
      t.uuid :outbox_event_id, null: false
    end
    add_tenant_reference :notifications, :memberships, column: :recipient_membership_id, null: false, index: false

    # One notification per recipient and event: handlers can safely run again.
    add_index :notifications, %i[organization_id outbox_event_id recipient_membership_id kind], unique: true,
      name: "index_notifications_dedup"
    add_index :notifications, %i[organization_id recipient_membership_id created_at],
      name: "index_notifications_inbox", order: { created_at: :desc }
  end
end
