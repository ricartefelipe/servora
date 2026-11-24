# frozen_string_literal: true

module Memberships
  # Removes access immediately: the next request of the member is denied by
  # TenantController because the membership is no longer active.
  class Deactivate
    def initialize(membership:, actor:)
      @membership = membership
      @actor = actor
    end

    def call
      Membership.transaction(requires_new: true) do
        OwnerGuard.new(@membership.organization).ensure_other_owner_remains!(@membership) if @membership.owner?
        @membership.update!(status: "deactivated", deactivated_at: Time.current, deactivated_by_user_id: @actor.id)
        AuditEvent.record!(action: "membership.deactivated", auditable: @membership,
          changes: { user_id: @membership.user_id, role: @membership.role })
      end
      @membership
    end
  end
end
