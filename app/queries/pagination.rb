# frozen_string_literal: true

# Offset pagination with a hard upper bound on page size. Fetches one extra row
# to know whether a next page exists, avoiding COUNT(*) on large tables.
class Pagination
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  attr_reader :page, :per_page

  def initialize(scope, page: 1, per_page: DEFAULT_PER_PAGE)
    @scope = scope
    @page = [page.to_i, 1].max
    @per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
  end

  def records
    load
    @records
  end

  def next_page?
    load
    @next_page
  end

  def previous_page?
    page > 1
  end

  private

  def load
    return if defined?(@records)

    rows = @scope.offset((page - 1) * per_page).limit(per_page + 1).to_a
    @next_page = rows.size > per_page
    @records = rows.first(per_page)
  end
end
