# frozen_string_literal: true

module TestSupport
  # Connection with the owner role, used only to clean data committed by
  # examples that disable transactional tests. It bypasses RLS because the
  # owner role owns the tables (policies are not forced).
  class MaintenanceRecord < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord -- separate owner connection
    self.abstract_class = true
    connects_to database: { writing: :maintenance }

    # Platform reference data (plans, modules) is loaded once by db:privileges:apply.
    PRESERVED_TABLES = %w[schema_migrations ar_internal_metadata plans plan_modules].freeze

    def self.truncate_all!
      tables = connection.tables - PRESERVED_TABLES
      return if tables.empty?

      quoted = tables.map { |table| connection.quote_table_name(table) }.join(", ")
      connection.execute("TRUNCATE TABLE #{quoted} RESTART IDENTITY CASCADE")
    end
  end
end

# Examples tagged `:committed` run without the wrapping test transaction so
# that commits, row locks, constraint checks and concurrent connections behave
# exactly as in production. Data is removed afterwards with the owner role.
#
# Implemented as a module included by metadata: rspec-rails' FixtureSupport is
# included first and resets use_transactional_tests, so this inclusion must
# come after it (a shared_context would be applied too early).
module CommittedTransactions
  def self.included(group)
    group.use_transactional_tests = false
    group.after { TestSupport::MaintenanceRecord.truncate_all! }
  end
end

RSpec.configure do |config|
  config.include CommittedTransactions, :committed

  config.before(:each, :committed) do
    raise "transactional tests are still enabled" if self.class.use_transactional_tests

    # Each thread must get its own connection (no shared test connection).
    ActiveRecord::Base.connection_pool.unlock_thread if ActiveRecord::Base.connection_pool.respond_to?(:unlock_thread)
  end
end
