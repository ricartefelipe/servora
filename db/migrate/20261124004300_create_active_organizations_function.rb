# frozen_string_literal: true

class CreateActiveOrganizationsFunction < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION servora_active_organizations() RETURNS TABLE (organization_id uuid)
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $$ SELECT id FROM organizations WHERE status = 'active' ORDER BY id $$;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS servora_active_organizations()"
  end
end
