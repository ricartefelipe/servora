# frozen_string_literal: true

# Base class for rows owned by an organization.
#
# Isolation is enforced by PostgreSQL (RLS + composite foreign keys); this
# class only declares the association. Queries must still start from an
# explicit scope (current organization or policy scope) — default_scope is
# intentionally not used as a security mechanism.
class TenantRecord < ApplicationRecord
  self.abstract_class = true

  belongs_to :organization
end
