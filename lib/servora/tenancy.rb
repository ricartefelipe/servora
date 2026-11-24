# frozen_string_literal: true

module Servora
  # Transaction-scoped tenant context for PostgreSQL Row-Level Security.
  #
  # The context is written with set_config(name, value, is_local => true), so it
  # lives only until the end of the enclosing transaction and can never leak to
  # another request through a pooled connection. Every RLS policy compares rows
  # with servora_current_organization_id(); without a context no tenant row is
  # visible or writable.
  #
  # Nested use is supported: the block runs inside a savepoint and the previous
  # context is restored when it finishes. If the block raises, rolling back the
  # savepoint also reverts the settings.
  #
  # Callers must not perform network I/O inside the block (it holds a
  # transaction open); jobs split work into short blocks around external calls.
  module Tenancy
    class MissingContext < StandardError; end
    class InvalidIdentifier < ArgumentError; end

    ORGANIZATION_SETTING = "servora.organization_id"
    USER_SETTING = "servora.user_id"
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    module_function

    def with_context(organization_id: nil, user_id: nil, model: ActiveRecord::Base, &)
      raise MissingContext, "an organization or a user is required" if organization_id.blank? && user_id.blank?

      organization_id = normalize(organization_id)
      user_id = normalize(user_id)

      model.transaction(requires_new: true) do
        connection = model.connection
        previous = read(connection)
        write(connection, organization_id, user_id)
        run_and_restore(connection, previous, &)
      end
    end

    def with_organization(organization_id, user_id: nil, &)
      raise MissingContext, "organization is required" if organization_id.blank?

      with_context(organization_id:, user_id:, &)
    end

    def current_organization_id(connection = ActiveRecord::Base.connection)
      read(connection).first
    end

    def current_user_id(connection = ActiveRecord::Base.connection)
      read(connection).last
    end

    def run_and_restore(connection, previous)
      completed = false
      result = yield
      completed = true
      result
    ensure
      # On exceptions the savepoint rollback already restores the settings and
      # the transaction may be aborted, so SQL must not be issued here.
      write(connection, *previous) if completed
    end

    def read(connection)
      row = connection.select_rows(
        "SELECT current_setting('#{ORGANIZATION_SETTING}', true), current_setting('#{USER_SETTING}', true)",
        "TENANT"
      ).first
      row.map(&:presence)
    end

    def write(connection, organization_id, user_id)
      sql = ActiveRecord::Base.sanitize_sql_array(
        ["SELECT set_config(?, ?, true), set_config(?, ?, true)",
         ORGANIZATION_SETTING, organization_id.to_s, USER_SETTING, user_id.to_s]
      )
      connection.select_rows(sql, "TENANT")
      # Cached SELECT results from a different context must never be reused.
      connection.clear_query_cache
    end

    def normalize(value)
      return nil if value.blank?

      string = value.to_s
      raise InvalidIdentifier, "tenant identifiers must be UUIDs" unless UUID_FORMAT.match?(string)

      string.downcase
    end

    private_class_method :run_and_restore, :read, :write, :normalize
  end
end
