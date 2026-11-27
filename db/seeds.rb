# frozen_string_literal: true

# Idempotent demonstration data. Executed with the application role (see
# bin/db-prepare), therefore every insert goes through Row-Level Security.
#
# The test database starts empty: `db:prepare` loads seeds whenever it creates
# a database, which in CI would leave demonstration data, recorded at the real
# time, behind for examples that expect a clean slate. Specs that need the
# seeds load this file with SERVORA_TEST_SEEDS=1 (DemoStoryHelpers#load_seeds).
return if Rails.env.test? && ENV.fetch("SERVORA_TEST_SEEDS", "0") != "1"

Rails.root.glob("db/seeds/*.rb").each { |file| load file }
