# frozen_string_literal: true

module Inventory
  class InsufficientAvailable < Error
    attr_reader :available, :requested

    def initialize(available, requested)
      @available = available
      @requested = requested
      super("available #{available.to_s("F")} is lower than requested #{requested.to_s("F")}")
    end
  end
end
