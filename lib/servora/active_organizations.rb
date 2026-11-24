# frozen_string_literal: true

module Servora
  # Iterates over active organizations for recurring jobs. The list comes from
  # a SECURITY DEFINER function that returns identifiers only; every unit of
  # work then runs inside that organization's RLS context.
  module ActiveOrganizations
    module_function

    def ids
      ActiveRecord::Base.connection.select_values("SELECT organization_id FROM servora_active_organizations()")
    end

    def each_id(&)
      ids.each(&)
    end
  end
end
