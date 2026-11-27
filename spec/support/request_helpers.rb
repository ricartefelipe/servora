# frozen_string_literal: true

module RequestHelpers
  # Signs in through Warden (session registry hooks run) and selects the
  # membership's organization through the real endpoint.
  def sign_in_as(membership)
    sign_in membership.user
    post select_organization_path(membership.organization_id)
  end
end

# System specs cannot issue POSTs directly: the organization is chosen through
# the picker, which opens automatically when there is a single membership and
# then lands on the dashboard (or the field area for technicians).
module SystemLoginHelpers
  def sign_in_as(membership)
    sign_in membership.user
    visit organizations_path
    click_on membership.organization.name if page.has_current_path?(organizations_path, wait: 0)
  end
end

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include RequestHelpers, type: :request
  config.include SystemLoginHelpers, type: :system
  config.before(:each, type: :request) { Rails.cache.clear }
end
