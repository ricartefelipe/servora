# frozen_string_literal: true

module Memberships
  # Guarantees that an organization always keeps at least one active owner.
  # Owner rows are locked in a consistent order so that two owners demoting or
  # deactivating each other concurrently cannot both succeed.
  class OwnerGuard
    class LastOwner < Servora::RuleViolation; end

    def initialize(organization)
      @organization = organization
    end

    def ensure_other_owner_remains!(membership)
      owners = @organization.memberships.active.where(role: "owner").order(:id).lock.pluck(:id)
      return unless owners == [membership.id]

      raise LastOwner, "A organização precisa manter ao menos um proprietário ativo."
    end
  end
end
