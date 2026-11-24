# frozen_string_literal: true

module Stock
  class AdjustmentsController < BaseController
    def new
      authorize StockBalance, :adjust?
      @form = StockAdjustmentForm.new(preselection)
      load_options
    end

    def create
      authorize StockBalance, :adjust?
      @form = StockAdjustmentForm.new(params.expect(stock_adjustment: StockAdjustmentForm.fields))
      submit(@form, notice: "Ajuste registrado e auditado.")
    end
  end
end
