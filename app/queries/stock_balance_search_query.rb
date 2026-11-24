# frozen_string_literal: true

# Stock positions for the inventory screen. Rows that never held stock and
# have no threshold are hidden; filters are explicit and parameterized.
class StockBalanceSearchQuery
  RELEVANT_SQL = "stock_balances.on_hand > 0 OR stock_balances.reserved > 0 OR stock_balances.minimum_quantity > 0"

  Summary = Data.define(:positions, :below_minimum, :stock_value)

  def initialize(scope, warehouse: nil, term: nil, below_minimum: false)
    @scope = scope
    @warehouse = warehouse
    @term = term.to_s.squish.presence
    @below_minimum = below_minimum
  end

  def call
    relation = filtered.includes(:catalog_item, :warehouse).order("catalog_items.name", "warehouses.name")
    @below_minimum ? relation.below_minimum : relation
  end

  # Totals for the selected warehouse and search, ignoring the "below minimum" toggle.
  def summary
    positions, below, value = filtered.pick(
      Arel.sql("count(*)"),
      Arel.sql("count(*) FILTER (WHERE #{StockBalance::BELOW_MINIMUM_SQL})"),
      Arel.sql("coalesce(sum(round(stock_balances.on_hand * stock_balances.average_cost, 2)), 0)")
    )
    Summary.new(positions:, below_minimum: below, stock_value: value)
  end

  private

  def filtered
    relation = @scope.joins(:catalog_item, :warehouse).where(RELEVANT_SQL)
    relation = relation.where(warehouse_id: @warehouse.id) if @warehouse
    return relation unless @term

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
    relation.where("catalog_items.name ILIKE :pattern OR catalog_items.sku ILIKE :pattern", pattern:)
  end
end
