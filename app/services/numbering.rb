# frozen_string_literal: true

# Human-readable sequential numbers per organization and year, e.g.
# ORC-2026-00042. Allocation is atomic; numbers consumed by a rolled back
# transaction are not reused (gaps are acceptable, duplicates are not).
module Numbering
  PREFIXES = { "quote" => "ORC", "work_order" => "OS", "receivable" => "FAT", "contract" => "CTR" }.freeze

  module_function

  def next!(organization:, scope:, at: Time.current)
    prefix = PREFIXES.fetch(scope)
    year = at.in_time_zone(organization.zone).year
    value = OrganizationCounter.next_value!(organization_id: organization.id, scope:, year:)
    format("%<prefix>s-%<year>d-%<value>05d", prefix:, year:, value:)
  end
end
