# frozen_string_literal: true

# Request/job metadata used for auditing and logging correlation only. It is
# never used to decide access: authorization uses the membership resolved by
# the controller and the database context set by Servora::Tenancy.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :membership, :organization, :portal_contact, :api_credential
  attribute :request_id, :ip_address, :user_agent

  def actor_label
    [user, portal_contact, api_credential].compact.first&.name
  end

  def actor_type
    if api_credential then "api_credential"
    elsif portal_contact then "portal_contact"
    elsif user then "user"
    else "system"
    end
  end
end
