# frozen_string_literal: true

require "rails_helper"

RSpec.describe Servora::DatabasePrivileges do
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }

  before do
    allow(connection).to receive(:quote_column_name) { |name| %("#{name}") }
    allow(connection).to receive(:quote_table_name) { |name| %("#{name}") }
    allow(connection).to receive_messages(tables: %w[audit_events plans customers], select_values: ["servora_resolve(text)"])
  end

  it "revokes mutation of history tables and reference data from the application role" do
    statements = described_class.new(connection:, app_role: "servora_app").statements

    expect(statements).to include(%(REVOKE UPDATE, DELETE ON "audit_events" FROM "servora_app"))
    expect(statements).to include(%(REVOKE INSERT, UPDATE, DELETE ON "plans" FROM "servora_app"))
    expect(statements.grep(/customers/)).to be_empty
  end

  it "restricts SECURITY DEFINER functions to the application role" do
    statements = described_class.new(connection:, app_role: "servora_app").statements

    expect(statements).to include("REVOKE ALL ON FUNCTION servora_resolve(text) FROM PUBLIC")
    expect(statements).to include(%(GRANT EXECUTE ON FUNCTION servora_resolve(text) TO "servora_app"))
  end

  it "executes every statement on the connection" do
    allow(connection).to receive(:execute)

    described_class.new(connection:, app_role: "servora_app").apply!

    expect(connection).to have_received(:execute).at_least(6).times
  end
end
