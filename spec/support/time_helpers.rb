# frozen_string_literal: true

# travel_to / freeze_time for rules that depend on the current date.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
