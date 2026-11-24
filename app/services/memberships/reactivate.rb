# frozen_string_literal: true

module Memberships
  class Reactivate
    def initialize(membership:)
      @membership = membership
    end

    def call
      Subscriptions::Seats.ensure_available!(@membership.organization_id) if @membership.technician?
      @membership.update!(status: "active", deactivated_at: nil, deactivated_by_user_id: nil)
      AuditEvent.record!(action: "membership.reactivated", auditable: @membership, changes: { user_id: @membership.user_id })
      @membership
    end
  end
end
