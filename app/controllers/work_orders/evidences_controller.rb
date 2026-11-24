# frozen_string_literal: true

module WorkOrders
  # Upload, authorized download and removal of work order evidences. Files are
  # streamed by this controller (Active Storage routes are disabled).
  class EvidencesController < TenantController
    include FileDelivery

    before_action :load_work_order

    def show
      authorize @work_order, :show?
      evidence = load_evidence
      deliver_file(evidence.file.download, filename: evidence.file.filename.to_s, type: evidence.content_type,
        inline: evidence.photo?)
    end

    def create
      authorize @work_order, :add_evidence?
      attributes = params.expect(evidence: %i[file caption])
      Evidences::Upload.new(work_order: @work_order, file: attributes[:file], caption: attributes[:caption],
        actor: current_membership).call
      back(notice: "Anexo enviado.")
    rescue Servora::RuleViolation => e
      back(alert: e.message)
    end

    def destroy
      authorize @work_order, :remove_evidence?
      Evidences::Remove.new(evidence: load_evidence, actor: current_membership).call
      back(notice: "Anexo removido.")
    rescue Servora::RuleViolation => e
      back(alert: e.message)
    end

    private

    def load_work_order
      @work_order = policy_scope(tenant_relation(WorkOrder)).includes(:assignments).find(params.expect(:work_order_id))
    end

    def load_evidence
      tenant_relation(WorkOrderEvidence).where(work_order_id: @work_order.id).includes(file_attachment: :blob)
        .find(params.expect(:id))
    end

    def back(**flash) = redirect_to(work_order_path(@work_order, anchor: "anexos"), status: :see_other, **flash)
  end
end
