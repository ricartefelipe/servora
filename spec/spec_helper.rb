# frozen_string_literal: true

# Loaded first by every spec (see .rspec). SimpleCov must start before any
# application file is required so that coverage is attributed correctly.
require_relative "support/coverage"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.max_formatted_output_length = 500
  end

  config.mock_with :rspec do |mocks|
    # Doubles must match real interfaces at the external boundaries.
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.profile_examples = 5 if ENV["CI"]

  # Random order with a printed seed: reproduce with `rspec --seed <seed>`.
  config.order = :random
  Kernel.srand config.seed
end
