# frozen_string_literal: true

# Idempotent demonstration data. Executed with the application role (see
# bin/db-prepare), therefore every insert goes through Row-Level Security.
Rails.root.glob("db/seeds/*.rb").each { |file| load file }
