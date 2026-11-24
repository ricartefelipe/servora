# frozen_string_literal: true

# Snapshot of the contract terms at each revision (append-only).
class ContractVersion < TenantRecord
  belongs_to :contract, inverse_of: :versions
  belongs_to :created_by, class_name: "Membership", foreign_key: :created_by_membership_id, optional: true, inverse_of: false

  def readonly? = persisted?
end
