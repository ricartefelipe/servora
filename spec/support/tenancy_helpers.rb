# frozen_string_literal: true

# Helpers to run code inside an organization's RLS context in specs.
module TenancyHelpers
  def in_tenant(organization_or_id, user: nil, &)
    organization_id = organization_or_id.respond_to?(:id) ? organization_or_id.id : organization_or_id
    Servora::Tenancy.with_context(organization_id:, user_id: user&.id, &)
  end

  def as_member(membership, &)
    Current.set(user: membership.user, membership:, organization: membership.organization) do
      in_tenant(membership.organization_id, user: membership.user, &)
    end
  end
end

RSpec.configure do |config|
  config.include TenancyHelpers
  config.after { Current.reset }
end
