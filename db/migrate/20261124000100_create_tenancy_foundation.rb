# frozen_string_literal: true

# Database primitives shared by every tenant table.
#
# servora_current_organization_id() and servora_current_user_id() read the
# transaction-local settings written by Servora::Tenancy (set_config(..., true)).
# Missing or empty settings return NULL, and since NULL never equals a column
# value every RLS policy denies access when no context is present.
class CreateTenancyFoundation < ActiveRecord::Migration[8.1]
  def up
    enable_extension "btree_gist"

    execute <<~SQL
      CREATE FUNCTION servora_current_organization_id() RETURNS uuid
        LANGUAGE sql STABLE PARALLEL SAFE
        AS $$ SELECT NULLIF(current_setting('servora.organization_id', true), '')::uuid $$;

      CREATE FUNCTION servora_current_user_id() RETURNS uuid
        LANGUAGE sql STABLE PARALLEL SAFE
        AS $$ SELECT NULLIF(current_setting('servora.user_id', true), '')::uuid $$;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS servora_current_user_id();
      DROP FUNCTION IF EXISTS servora_current_organization_id();
    SQL
    disable_extension "btree_gist"
  end
end
