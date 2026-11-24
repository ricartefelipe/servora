# frozen_string_literal: true

module TestSupport
  # Connection with the owner role, used only to clean data committed by
  # examples that disable transactional tests. It bypasses RLS because the
  # owner role owns the tables (policies are not forced).
  class MaintenanceRecord < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord -- separate owner connection
    self.abstract_class = true
    connects_to database: { writing: :maintenance }

    PRESERVED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

    def self.truncate_all!
      tables = connection.tables - PRESERVED_TABLES
      return if tables.empty?

      quoted = tables.map { |table| connection.quote_table_name(table) }.join(", ")
      connection.execute("TRUNCATE TABLE #{quoted} RESTART IDENTITY CASCADE")
    end
  end
end

# Examples tagged `committed: true` run without the wrapping test transaction so
# that commits, row locks, constraint checks and concurrent connections behave
# exactly as in production. Data is removed afterwards.
RSpec.shared_context "with committed transactions", :committed do
  self.use_transactional_tests = false

  after do
    TestSupport::MaintenanceRecord.truncate_all!
  end
end
