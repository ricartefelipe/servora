# frozen_string_literal: true

# Helper for pure rule specs (spec/unit). It deliberately does NOT boot Rails:
# no database, browser or network is available, so any accidental dependency
# on Active Record raises NameError. Only Active Support core extensions and
# the app/domain directory are loaded.
require "bigdecimal"
require "active_support"
require "active_support/core_ext"
require "zeitwerk"

module UnitSuite
  def self.loader
    @loader ||= Zeitwerk::Loader.new.tap do |loader|
      domain_dir = File.expand_path("../app/domain", __dir__)
      loader.push_dir(domain_dir) if File.directory?(domain_dir)
      loader.setup
    end
  end
end

UnitSuite.loader
Time.zone_default = Time.find_zone!("America/Sao_Paulo")

RSpec.configure do |config|
  config.before(:suite) do
    raise "spec/unit must run without Rails (use bin/test-unit)" if defined?(Rails.application)
  end
end
