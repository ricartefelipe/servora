# frozen_string_literal: true

require "rails_helper"

# Guards the deployment invariant behind Row-Level Security: the runtime role
# must not be able to bypass policies.
RSpec.describe "Database roles" do
  let(:connection) { ActiveRecord::Base.connection }

  it "connects the application with a role that cannot bypass RLS" do
    role = connection.select_one(<<~SQL.squish)
      SELECT rolname, rolsuper, rolbypassrls, rolcreatedb, rolcreaterole
      FROM pg_roles WHERE rolname = current_user
    SQL

    expect(role).to include("rolsuper" => false, "rolbypassrls" => false, "rolcreatedb" => false, "rolcreaterole" => false)
    expect(role["rolname"]).to eq(ENV.fetch("DB_APP_USER", "servora_app"))
  end

  it "does not let the application role own any table" do
    owned = connection.select_values(<<~SQL.squish)
      SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tableowner = current_user
    SQL

    expect(owned).to be_empty
  end

  it "forbids DDL for the application role" do
    expect do
      connection.execute("CREATE TABLE intruder (id int)")
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end

  it "returns no tenant context unless one is set in the transaction" do
    expect(connection.select_value("SELECT servora_current_organization_id()")).to be_nil

    connection.transaction do
      connection.execute("SELECT set_config('servora.organization_id', '', true)")
      expect(connection.select_value("SELECT servora_current_organization_id()")).to be_nil
    end
  end
end
