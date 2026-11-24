# frozen_string_literal: true

# Active Storage tables made tenant-aware, and work order evidences.
#
# Blobs, attachments and variant records carry organization_id, filled by the
# database from the transaction's tenant context and protected by the same
# Row-Level Security policy as every tenant table: a blob of another
# organization is invisible even if its id or key leaks. Default Active
# Storage routes are disabled; downloads go through authorized controllers.
class CreateAttachments < ActiveRecord::Migration[8.1]
  include Servora::MigrationHelpers

  TENANT_DEFAULT = -> { "servora_current_organization_id()" }

  def change
    create_storage_tables
    create_evidences
  end

  private

  def create_storage_tables
    create_table :active_storage_blobs, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :organization_id, null: false, default: TENANT_DEFAULT
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index :active_storage_blobs, :key, unique: true
    add_index :active_storage_blobs, %i[organization_id id], unique: true, name: "index_active_storage_blobs_on_tenant_key"

    create_table :active_storage_attachments, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :organization_id, null: false, default: TENANT_DEFAULT
      t.string :name, null: false
      t.string :record_type, null: false
      t.uuid :record_id, null: false
      t.uuid :blob_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :active_storage_attachments, :blob_id
    add_index :active_storage_attachments, %i[record_type record_id name blob_id], unique: true,
      name: "index_active_storage_attachments_uniqueness"
    add_foreign_key :active_storage_attachments, :active_storage_blobs, column: %i[organization_id blob_id],
      primary_key: %i[organization_id id], name: "fk_active_storage_attachments_blob_tenant"

    create_table :active_storage_variant_records, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :organization_id, null: false, default: TENANT_DEFAULT
      t.uuid :blob_id, null: false
      t.string :variation_digest, null: false
    end
    add_index :active_storage_variant_records, %i[blob_id variation_digest], unique: true,
      name: "index_active_storage_variant_records_uniqueness"
    add_foreign_key :active_storage_variant_records, :active_storage_blobs, column: %i[organization_id blob_id],
      primary_key: %i[organization_id id], name: "fk_active_storage_variant_records_blob_tenant"

    %i[active_storage_blobs active_storage_attachments active_storage_variant_records].each do |table|
      add_foreign_key table, :organizations
      enable_tenant_isolation(table)
    end
  end

  def create_evidences
    create_tenant_table :work_order_evidences do |t|
      t.string :kind, null: false
      t.string :caption
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :original_filename, null: false
    end
    add_tenant_reference :work_order_evidences, :work_orders, column: :work_order_id, null: false
    add_tenant_reference :work_order_evidences, :memberships, column: :uploaded_by_membership_id, null: false, index: false
    add_inclusion_constraint :work_order_evidences, :kind, %w[photo document], name: "work_order_evidences_kind"
    add_check_constraint :work_order_evidences, "byte_size > 0", name: "work_order_evidences_size"
  end
end
