# frozen_string_literal: true

module Receivables
  # Pure financial position of a receivable (BRL, 2 decimals):
  #
  #   net amount = amount − discount
  #   net paid   = paid − refunded
  #   balance    = net amount − net paid
  #
  # Every operation returns a new position or raises Rejected. Overpayment,
  # discounts beyond the balance, refunds beyond what was paid and
  # cancellation with money kept are impossible by construction (and again by
  # database constraints).
  Position = Data.define(:amount, :discount, :paid, :refunded) do
    def self.issue(amount)
      value = money(amount)
      raise Rejected, "O valor da conta deve ser maior que zero." unless value.positive?

      new(amount: value, discount: BigDecimal("0"), paid: BigDecimal("0"), refunded: BigDecimal("0"))
    end

    def self.money(value) = Pricing::Amount.money(value)

    def net_amount = amount - discount
    def net_paid = paid - refunded
    def balance = net_amount - net_paid
    def settled? = balance.zero?

    def status
      return "paid" if settled?

      net_paid.positive? ? "partially_paid" : "open"
    end

    def pay(value)
      value = positive!(value, "pagamento")
      raise Rejected, "O pagamento (#{brl(value)}) supera o saldo em aberto (#{brl(balance)})." if value > balance

      with(paid: paid + value)
    end

    def grant_discount(value)
      value = positive!(value, "desconto")
      raise Rejected, "O desconto (#{brl(value)}) supera o saldo em aberto (#{brl(balance)})." if value > balance

      with(discount: discount + value)
    end

    def refund(value, refundable:)
      value = positive!(value, "estorno")
      limit = [refundable, net_paid].min
      raise Rejected, "O estorno (#{brl(value)}) supera o valor estornável (#{brl(limit)})." if value > limit

      with(refunded: refunded + value)
    end

    def ensure_cancelable!
      return if net_paid.zero?

      raise Rejected, "Estorne os pagamentos (#{brl(net_paid)}) antes de cancelar a conta."
    end

    private

    def positive!(value, label)
      amount = self.class.money(value)
      raise Rejected, "O valor do #{label} deve ser maior que zero." unless amount.positive?

      amount
    end

    def brl(value) = Pricing::Format.brl(value)
  end
end
