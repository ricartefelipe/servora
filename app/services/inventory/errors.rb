# frozen_string_literal: true

module Inventory
  # Translation of domain errors into user-facing rule violations.
  module Errors
    class Unavailable < Servora::RuleViolation; end
    class NotStockable < Servora::RuleViolation; end
    class InvalidOperation < Servora::RuleViolation; end
    KeyReused = IdempotentOperation::KeyReused

    module_function

    def translate(error, item_name)
      case error
      when Inventory::InsufficientAvailable
        Unavailable.new("Saldo disponível insuficiente de #{item_name}: disponível #{format(error.available)}, " \
                        "solicitado #{format(error.requested)}.")
      else
        InvalidOperation.new("Operação de estoque inválida para #{item_name}: #{error.message}.")
      end
    end

    def format(value) = value.to_s("F").delete_suffix(".0")

    # Lock order for every inventory operation: work order → reservation or
    # consumption → balances (sorted). Locking the order first serializes
    # reservations and consumptions with cancellation and completion.
    def lock_open_work_order!(work_order)
      work_order.lock!
      raise InvalidOperation, "A ordem #{work_order.number} está encerrada." if work_order.finished?
    end

    def ensure_stockable!(item)
      return if item.part? && item.tracks_inventory?

      raise NotStockable, "#{item.name} não controla estoque."
    end
  end
end
