# frozen_string_literal: true

module Stock
  class ReceiptsController < BaseController
    def new
      authorize StockBalance, :receive?
      @form = StockReceiptForm.new(preselection)
      load_options
    end

    def create
      authorize StockBalance, :receive?
      @form = StockReceiptForm.new(params.expect(stock_receipt: StockReceiptForm.fields))
      submit(@form, notice: "Entrada registrada.")
    end
  end
end
