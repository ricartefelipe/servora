# frozen_string_literal: true

require "csv"

module Reports
  # CSV with semicolons (spreadsheet default in pt-BR), BOM for UTF-8
  # detection and every cell neutralized against formula injection.
  module CsvExport
    module_function

    def generate(report)
      body = CSV.generate(col_sep: ";") do |csv|
        csv << report.headers.map { |header| CsvCell.safe(header) }
        report.rows(limit: Base::EXPORT_ROWS).each { |row| csv << row.map { |cell| CsvCell.safe(cell) } }
      end
      "﻿#{body}"
    end
  end
end
