# frozen_string_literal: true

require "capybara/rspec"
require "capybara/cuprite"

Capybara.register_driver(:servora_cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1400, 1000],
    browser_path: ENV.fetch("BROWSER_PATH", nil),
    browser_options: { "no-sandbox" => nil, "disable-dev-shm-usage" => nil },
    process_timeout: 30,
    timeout: 15,
    inspector: false,
    headless: ENV.fetch("HEADLESS", "true") != "false"
  )
end

Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }
Capybara.disable_animation = true
Capybara.save_path = Rails.root.join("tmp/capybara")

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, :js, type: :system) do
    driven_by :servora_cuprite
  end
end
