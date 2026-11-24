# frozen_string_literal: true

module WorkOrders
  # Diagnosis and applied solution, with optimistic locking.
  class UpdateTechnicalReport
    class NotAllowed < Servora::RuleViolation; end

    def initialize(work_order:, diagnosis:, solution:, expected_version: nil)
      @work_order = work_order
      @diagnosis = diagnosis
      @solution = solution
      @expected_version = expected_version
    end

    def call
      raise NotAllowed, "A ordem está encerrada." if @work_order.finished?

      @work_order.lock_version = Integer(@expected_version) if @expected_version.present?
      @work_order.update!(diagnosis: @diagnosis.to_s.strip.presence, solution: @solution.to_s.strip.presence)
      @work_order
    end
  end
end
