# frozen_string_literal: true

module Organizations
  # Creates an organization and makes the requesting user its owner.
  #
  # The primary key is generated before the insert so the tenant context can be
  # opened for the new organization: the RLS policy only allows inserting an
  # organization (and its memberships) inside its own context.
  class Register
    Result = Data.define(:organization, :membership)

    def initialize(user:, attributes:)
      @user = user
      @attributes = attributes
    end

    def call
      organization_id = SecureRandom.uuid_v7

      Servora::Tenancy.with_context(organization_id:, user_id: @user.id) do
        organization = Organization.create!(@attributes.merge(id: organization_id))
        membership = organization.memberships.create!(user: @user, role: "owner")
        Subscriptions::StartTrial.new(organization:).call
        Current.set(user: @user, membership:, organization:) do
          AuditEvent.record!(action: "organization.created", organization:, auditable: organization,
            changes: organization.attributes.slice("name", "segment", "time_zone"))
        end
        Result.new(organization:, membership:)
      end
    end
  end
end
