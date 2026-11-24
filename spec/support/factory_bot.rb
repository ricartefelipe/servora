# frozen_string_literal: true

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end

# Tenant rows can only be written inside their organization's RLS context.
# Factories persist through the same mechanism the application uses, so specs
# never need (or get) a bypass.
FactoryBot.define do
  to_create do |instance|
    organization_id =
      if instance.is_a?(Organization) then instance.id ||= SecureRandom.uuid_v7
      elsif instance.respond_to?(:organization_id) then instance.organization_id
      end

    if organization_id
      Servora::Tenancy.with_organization(organization_id) { instance.save! }
    else
      instance.save!
    end
  end
end
