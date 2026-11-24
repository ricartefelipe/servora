# frozen_string_literal: true

module Reports
  # Material consumed by work orders in the period (net of returns), per item;
  # cost at the historical consumption cost with the cost permission.
  class MaterialsReport < Base
    NET_QUANTITY = "(material_consumptions.quantity - material_consumptions.returned_quantity)"

    def title = "Consumo de materiais"

    def summary
      data = items
      figures = { "Itens consumidos" => data.size,
                  "Ordens com consumo" => MaterialConsumption.where(created_at: range).distinct.count(:work_order_id) }
      @show_costs ? figures.merge("Custo total de material" => data.sum(Money.of(0)) { |row| row[:cost] }) : figures
    end

    def headers = @show_costs ? ["Item", "Unidade", "Quantidade líquida", "Custo"] : ["Item", "Unidade", "Quantidade líquida"]

    def rows(limit:)
      items.first(limit).map do |row|
        @show_costs ? row.values_at(:name, :unit, :quantity, :cost) : row.values_at(:name, :unit, :quantity)
      end
    end

    private

    def items
      @items ||= MaterialConsumption.joins(:catalog_item).where(created_at: range)
        .group("catalog_items.name", "catalog_items.unit")
        .order(Arel.sql("sum(#{NET_QUANTITY}) DESC"))
        .pluck("catalog_items.name", "catalog_items.unit", Arel.sql("sum(#{NET_QUANTITY})"),
          Arel.sql("sum(round(#{NET_QUANTITY} * material_consumptions.unit_cost, 2))"))
        .map { |name, unit, quantity, cost| { name:, unit:, quantity: Pricing::Amount.quantity(quantity), cost: money(cost) } }
    end
  end
end
