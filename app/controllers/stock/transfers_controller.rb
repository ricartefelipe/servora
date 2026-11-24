# frozen_string_literal: true

module Stock
  class TransfersController < BaseController
    def new
      authorize StockBalance, :transfer?
      @form = StockTransferForm.new(preselection)
      load_options
    end

    def create
      authorize StockBalance, :transfer?
      @form = StockTransferForm.new(params.expect(stock_transfer: StockTransferForm.fields))
      submit(@form, notice: "Transferência registrada.")
    end
  end
end
