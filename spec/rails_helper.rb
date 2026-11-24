# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"

Rails.root.glob("spec/support/**/*.rb").sort.each { |file| require file }

# The test database is prepared with the owner role (RAILS_ENV=test bin/db-prepare);
# the suite itself connects with the application role and cannot run DDL.
begin
  ActiveRecord::Migration.check_all_pending!
rescue ActiveRecord::PendingMigrationError => e
  abort "#{e.message}\nRun: RAILS_ENV=test ruby bin/db-prepare"
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
