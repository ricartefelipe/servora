# frozen_string_literal: true

return if ENV["COVERAGE"] == "false"

require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch
  primary_coverage :line

  # Each suite (unit without Rails, Rails-backed) records its own result; they
  # are merged and checked by bin/coverage-check.
  command_name ENV.fetch("COVERAGE_SUITE", "rspec")
  merging true
  merge_timeout 3600

  cover "{app,lib}/**/*.rb"

  # Justified exclusions: framework generated base classes without behaviour and
  # one-off rake/migration support that is exercised by CI database tasks.
  skip "/spec/"
  skip "/config/"
  skip "/db/"
  skip "app/channels/application_cable/connection.rb"
  skip "lib/tasks/"

  group "Domínio (regras puras)", "app/domain"
  group "Casos de uso", "app/services"
  group "Consultas", "app/queries"
  group "Formulários", "app/forms"
  group "Policies", "app/policies"
  group "Models", "app/models"
  group "Controllers", "app/controllers"
  group "Jobs", "app/jobs"
  group "Integrações", "app/integrations"
  group "Infraestrutura", "lib/servora"

  # Thresholds are enforced on the merged result (bin/coverage-check).
  minimum_coverage 0
end
