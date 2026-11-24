# frozen_string_literal: true

module Inventory
  # Replaying an operation with the same idempotency key returns the original
  # record instead of moving stock again.
  #
  # The key is looked up before the work starts. Concurrent duplicates are
  # caught by the partial unique index: the losing request's savepoint rolls
  # back and it returns the winner's record. A key reused with a different
  # payload is rejected instead of silently returning unrelated data.
  module Idempotency
    module_function

    def perform(key, find:, same:)
      return yield if key.nil?

      replay(find.call, same) || yield
    rescue ActiveRecord::RecordNotUnique
      raise if key.nil?

      replay(find.call, same) || raise
    end

    def replay(existing, same)
      return nil if existing.nil?
      return existing if same.call(existing)

      raise Errors::KeyReused, "Esta operação já foi registrada com outros dados. Recarregue a página e tente novamente."
    end
  end
end
