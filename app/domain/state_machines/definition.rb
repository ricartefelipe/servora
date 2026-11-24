# frozen_string_literal: true

module StateMachines
  # Explicit transition table. Invalid transitions raise InvalidTransition;
  # side effects live in the use cases, never in the machine.
  class Definition
    class InvalidTransition < StandardError
      attr_reader :from, :to

      def initialize(from, to, message = nil)
        @from = from
        @to = to
        super(message || "transition #{from} -> #{to} is not allowed")
      end
    end

    attr_reader :states

    def initialize(transitions)
      @transitions = transitions.transform_values { |targets| targets.map(&:to_s).freeze }.transform_keys(&:to_s).freeze
      @states = (@transitions.keys + @transitions.values.flatten).uniq.freeze
    end

    def allowed?(from, to)
      @transitions.fetch(from.to_s, []).include?(to.to_s)
    end

    def targets(from)
      @transitions.fetch(from.to_s, [])
    end

    def assert!(from, to)
      raise InvalidTransition.new(from, to) unless allowed?(from, to)

      to.to_s
    end

    def terminal?(state)
      targets(state).empty?
    end
  end
end
