# frozen_string_literal: true

module Servora
  # Grants the runtime (application) role exactly the privileges it needs.
  #
  # PostgreSQL dumps produced by Rails omit privileges (--no-privileges), so
  # grants are reapplied by `bin/rails db:privileges:apply` after every schema
  # load or migration, always executed with the owner role.
  #
  # Invariants enforced here:
  # * the application role never owns tables, so RLS applies to it;
  # * history tables are append-only (no UPDATE/DELETE);
  # * platform reference tables are read-only at runtime;
  # * SECURITY DEFINER functions are executable only by the application role.
  class DatabasePrivileges
    # Immutable history: rows are only ever inserted.
    APPEND_ONLY_TABLES = %w[
      audit_events
      equipment_events
      financial_events
      quote_events
      outbox_event_failures
      sla_clock_events
      stock_movements
      visit_transitions
      work_order_reports
      work_order_transitions
    ].freeze

    # Maintained exclusively by migrations or owner-run tasks.
    READ_ONLY_TABLES = %w[
      ar_internal_metadata
      schema_migrations
      plans
      plan_modules
    ].freeze

    def initialize(connection:, app_role:)
      @connection = connection
      @app_role = app_role
    end

    def apply!
      statements.each { |sql| @connection.execute(sql) }
    end

    def statements
      role = @connection.quote_column_name(@app_role)
      base = [
        "GRANT USAGE ON SCHEMA public TO #{role}",
        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role}",
        "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role}",
        "REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM #{role}"
      ]
      base + restricted_table_statements(role) + definer_function_statements(role)
    end

    private

    def restricted_table_statements(role)
      existing(APPEND_ONLY_TABLES).map { |table| "REVOKE UPDATE, DELETE ON #{quote(table)} FROM #{role}" } +
        existing(READ_ONLY_TABLES).map { |table| "REVOKE INSERT, UPDATE, DELETE ON #{quote(table)} FROM #{role}" }
    end

    def definer_function_statements(role)
      definer_functions.flat_map do |signature|
        [
          "REVOKE ALL ON FUNCTION #{signature} FROM PUBLIC",
          "GRANT EXECUTE ON FUNCTION #{signature} TO #{role}"
        ]
      end
    end

    def existing(tables)
      tables & @connection.tables
    end

    def definer_functions
      @connection.select_values(<<~SQL.squish)
        SELECT p.oid::regprocedure::text
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prosecdef AND p.proname LIKE 'servora\\_%'
        ORDER BY 1
      SQL
    end

    def quote(table)
      @connection.quote_table_name(table)
    end
  end
end
