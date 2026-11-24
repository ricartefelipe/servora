# frozen_string_literal: true

module WorkOrders
  # Answers a checklist item. expected_version (lock_version seen by the user
  # or by the offline draft) prevents silently overwriting a newer answer.
  class AnswerChecklist
    class Conflict < Servora::RuleViolation; end
    class NotAllowed < Servora::RuleViolation; end

    def initialize(item:, response:, actor:, expected_version: nil)
      @item = item
      @response = response.to_s.strip
      @actor = actor
      @expected_version = expected_version
    end

    def call
      raise NotAllowed, "A ordem está encerrada." if @item.work_order.finished?

      @item.with_lock do
        if @expected_version && @item.lock_version != Integer(@expected_version)
          raise Conflict, "O item \"#{@item.label}\" foi alterado por outra pessoa. Revise antes de salvar."
        end

        @item.update!(response: @response.presence, responded_at: Time.current, responded_by: @actor)
      end
      @item
    end
  end
end
