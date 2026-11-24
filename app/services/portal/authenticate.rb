# frozen_string_literal: true

module Portal
  # Resolves the organization of a portal session token (SECURITY DEFINER
  # function returning only the tenant id). The session itself is then loaded
  # under RLS by the portal controllers.
  module Authenticate
    module_function

    def organization_for(session_token)
      return nil if session_token.blank?

      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT servora_resolve_portal_session(?)",
                                               PortalAccessGrant.digest(session_token)])
      )
    end
  end
end
