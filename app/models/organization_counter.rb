# frozen_string_literal: true

class OrganizationCounter < TenantRecord
  # Allocates the next number atomically (single statement; concurrent callers
  # serialize on the row and never receive the same value).
  def self.next_value!(organization_id:, scope:, year:)
    sql = sanitize_sql_array([<<~SQL.squish, organization_id, scope, year])
      INSERT INTO organization_counters (organization_id, scope, year, value, created_at, updated_at)
      VALUES (?, ?, ?, 1, now(), now())
      ON CONFLICT (organization_id, scope, year)
      DO UPDATE SET value = organization_counters.value + 1, updated_at = now()
      RETURNING value
    SQL
    connection.select_value(sql)
  end
end
