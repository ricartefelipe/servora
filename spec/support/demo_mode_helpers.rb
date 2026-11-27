# frozen_string_literal: true

# Demo mode (Servora::Demo) follows ENV["SERVORA_DEMO"]. Examples tagged
# `demo_mode: true` run with it on, `demo_mode: false` with it explicitly off;
# untagged examples keep the process environment (off in the test service).
module DemoModeHelpers
  def with_environment(values)
    previous = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

RSpec.configure do |config|
  config.include DemoModeHelpers

  config.around do |example|
    next example.run unless example.metadata.key?(:demo_mode)

    previous = ENV.fetch("SERVORA_DEMO", nil)
    ENV["SERVORA_DEMO"] = example.metadata[:demo_mode] ? "1" : "0"
    example.run
  ensure
    ENV["SERVORA_DEMO"] = previous if example.metadata.key?(:demo_mode)
  end
end
