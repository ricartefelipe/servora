# frozen_string_literal: true

module Memberships
  class Update
    def initialize(membership:, attributes:)
      @membership = membership
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      Membership.transaction(requires_new: true) do
        if @membership.owner? && @attributes[:role].present? && @attributes[:role] != "owner"
          OwnerGuard.new(@membership.organization).ensure_other_owner_remains!(@membership)
        end
        if @attributes[:role].to_s == "technician" && !@membership.technician? && @membership.active?
          Subscriptions::Seats.ensure_available!(@membership.organization_id)
        end
        @membership.update!(@attributes)
        audit_changes
      end
      @membership
    end

    private

    def audit_changes
      changes = @membership.saved_changes.except("updated_at")
      return if changes.empty?

      AuditEvent.record!(action: "membership.updated", auditable: @membership, changes:)
    end
  end
end
