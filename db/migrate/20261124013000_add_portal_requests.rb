# frozen_string_literal: true

# Work orders opened by a customer contact through the portal: the requester
# is the contact (of the same customer, composite key) instead of a staff
# member; every work order keeps exactly one known origin of authorship.
class AddPortalRequests < ActiveRecord::Migration[8.1]
  def change
    add_index :customer_contacts, %i[organization_id customer_id id], unique: true,
      name: "index_customer_contacts_on_customer_key"
    add_column :work_orders, :requested_by_contact_id, :uuid
    add_foreign_key :work_orders, :customer_contacts, column: %i[organization_id customer_id requested_by_contact_id],
      primary_key: %i[organization_id customer_id id], name: "fk_work_orders_requested_by_contact"
    change_column_null :work_orders, :created_by_membership_id, true
    add_check_constraint :work_orders, "created_by_membership_id IS NOT NULL OR requested_by_contact_id IS NOT NULL",
      name: "work_orders_author"
  end
end
