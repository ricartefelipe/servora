# frozen_string_literal: true

module WorkOrders
  class ChecklistItemsController < TenantController
    before_action :load_work_order

    def update
      authorize @work_order, :update_execution?
      item = tenant_relation(WorkOrderChecklistItem).includes(:work_order).where(work_order_id: @work_order.id)
        .find(params.expect(:id))
      answer = params.expect(answer: %i[response lock_version])
      WorkOrders::AnswerChecklist.new(item:, response: answer[:response], actor: current_membership,
        expected_version: answer[:lock_version]).call
      redirect_to work_order_path(@work_order, anchor: "execucao"), notice: "Checklist atualizado.", status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      back_with_alert(e.record.errors.full_messages.to_sentence)
    rescue Servora::RuleViolation => e
      back_with_alert(e.message)
    end

    private

    def load_work_order
      @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
    end

    def back_with_alert(message)
      redirect_to work_order_path(@work_order, anchor: "execucao"), alert: message, status: :see_other
    end
  end
end
