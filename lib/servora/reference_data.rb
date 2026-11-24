# frozen_string_literal: true

module Servora
  # Platform reference data (plans and add-on modules). Loaded with the owner
  # role after schema loads and migrations (db:privileges:apply), with upserts
  # keyed by code: running it again updates prices and names without
  # duplicating rows. The application role can only read these tables.
  module ReferenceData
    PLANS = [
      { code: "essencial", name: "Essencial", monthly_price: "249.00", included_technicians: 3, extra_technician_price: "39.00",
        implementation_fee: "0.00", modules: [], trial_days: 14, position: 1 },
      { code: "profissional", name: "Profissional", monthly_price: "590.00", included_technicians: 10,
        extra_technician_price: "35.00", implementation_fee: "1500.00", modules: %w[inventory preventive], trial_days: 14,
        position: 2 },
      { code: "empresarial", name: "Empresarial", monthly_price: "1290.00", included_technicians: 30,
        extra_technician_price: "29.00", implementation_fee: "4000.00", modules: %w[inventory preventive finance api],
        trial_days: 14, position: 3 }
    ].freeze

    MODULES = [
      { code: "inventory", name: "Estoque e materiais", monthly_price: "120.00", position: 1 },
      { code: "preventive", name: "Contratos e manutenção preventiva", monthly_price: "90.00", position: 2 },
      { code: "finance", name: "Financeiro e cobranças", monthly_price: "150.00", position: 3 },
      { code: "api", name: "API e webhooks", monthly_price: "200.00", position: 4 }
    ].freeze

    module_function

    def load!(connection)
      return unless connection.table_exists?(:plans) && connection.table_exists?(:plan_modules)

      PLANS.each { |row| write_row(connection, "plans", row) }
      MODULES.each { |row| write_row(connection, "plan_modules", row) }
    end

    def write_row(connection, table, row)
      now = connection.quote(Time.current)
      columns = row.keys.map { |key| connection.quote_column_name(key) }
      values = row.values.map { |value| literal(connection, value) }
      updates = (row.keys - [:code]).map do |key|
        "#{connection.quote_column_name(key)} = EXCLUDED.#{connection.quote_column_name(key)}"
      end
      connection.execute(<<~SQL.squish)
        INSERT INTO #{connection.quote_table_name(table)} (#{columns.join(", ")}, created_at, updated_at)
        VALUES (#{values.join(", ")}, #{now}, #{now})
        ON CONFLICT (code) DO UPDATE SET #{updates.join(", ")}, updated_at = EXCLUDED.updated_at
      SQL
    end

    def literal(connection, value)
      return "ARRAY[#{value.map { |item| connection.quote(item) }.join(", ")}]::varchar[]" if value.is_a?(Array)

      connection.quote(value)
    end
  end
end
