# frozen_string_literal: true

module Reports
  # Billing, receipts and, with the cost permission, the realized margin of
  # the work orders completed in the period. Billed and received are reported
  # separately (accrual vs. cash).
  class FinanceReport < Base
    BALANCE = ReceivablesSummaryQuery::BALANCE_SQL
    NET_AMOUNT = "receivables.amount - receivables.discount_amount"
    MARGIN_FIELDS = %i[revenue cost margin].freeze
    COST_HEADERS = ["Ordem", "Concluída em", "Receita", "Material", "Mão de obra", "Despesas", "Margem"].freeze
    BILLING_HEADERS = ["Conta", "Ordem", "Emitida em", "Vencimento", "Valor", "Saldo", "Situação"].freeze

    def title = "Financeiro"

    def summary
      figures = cash_figures
      return figures unless @show_costs

      totals = margin_totals
      figures.merge("Receita das ordens concluídas" => totals[:revenue], "Custos dessas ordens" => totals[:cost],
        "Margem realizada" => totals[:margin])
    end

    def headers = @show_costs ? COST_HEADERS : BILLING_HEADERS

    def rows(limit:)
      if @show_costs
        return margin_rows.first(limit).map do |row|
          row.values_at(:number, :completed_at, *%i[revenue material labor expenses margin])
        end
      end

      billing_rows(limit)
    end

    private

    def cash_figures
      { "Faturado no período" => money(Receivable.active.where(created_at: range).sum(Arel.sql(NET_AMOUNT))),
        "Recebido no período" => money(Payment.where(paid_at: range).sum(:amount)),
        "Estornado no período" => money(FinancialEvent.where(kind: "refund", occurred_at: range).sum(:amount)),
        "Saldo em aberto hoje" => money(Receivable.outstanding.sum(Arel.sql(BALANCE))),
        "Vencido hoje" => money(Receivable.overdue(Time.zone.today).sum(Arel.sql(BALANCE))) }
    end

    def margin_totals
      margin_rows.each_with_object(Hash.new(Money.of(0))) do |row, totals|
        MARGIN_FIELDS.each { |field| totals[field] += row[field] }
      end
    end

    def billing_rows(limit)
      Receivable.where(created_at: range).joins(:work_order).order(:created_at).limit(limit)
        .pluck(:number, "work_orders.number", :created_at, :due_on, Arel.sql(NET_AMOUNT), Arel.sql(BALANCE), :status)
        .map do |row|
          number, order, issued, due, amount, balance, status = row
          [number, order, local(issued), due.strftime("%d/%m/%Y"), money(amount), money(balance), Receivable::STATUSES.fetch(status)]
        end
    end

    def margin_rows
      @margin_rows ||= WorkOrder.where(completed_at: range).order(:completed_at).limit(EXPORT_ROWS).map do |order|
        realized = WorkOrderFinancialsQuery.new(order).realized
        { number: order.number, completed_at: local(order.completed_at), revenue: money(realized.revenue),
          material: money(realized.material_cost), labor: money(realized.labor_cost), expenses: money(realized.expenses),
          cost: money(realized.total_cost), margin: money(realized.margin) }
      end
    end
  end
end
