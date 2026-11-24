# frozen_string_literal: true

module Field
  # Applies one operation from the field app (online or replayed from the
  # offline queue).
  #
  # * idempotent: the outcome is stored under the device-generated operation
  #   id; resending returns the stored outcome;
  # * permissions are checked by the caller on every request, never assumed
  #   from when the draft was written;
  # * conflicts: the draft carries the version it was based on; if the server
  #   record changed meanwhile, nothing is overwritten and the current server
  #   values are returned so the technician can decide.
  class Sync
    Operation = Data.define(:id, :kind, :version, :payload)

    def initialize(work_order:, membership:, operation:)
      @work_order = work_order
      @membership = membership
      @operation = operation
    end

    def call
      unless FieldOperation::KINDS.include?(@operation.kind)
        return { "operation_id" => @operation.id, "status" => "rejected", "result" => { "error" => "Operação desconhecida." } }
      end

      existing = FieldOperation.find_by(operation_id: @operation.id)
      return replay(existing) if existing

      status, result = apply
      store(status, result)
    rescue ActiveRecord::RecordNotUnique
      replay(FieldOperation.find_by!(operation_id: @operation.id))
    end

    private

    def replay(existing)
      return existing.response if existing.membership_id == @membership.id && existing.work_order_id == @work_order.id

      { "operation_id" => @operation.id, "status" => "rejected", "result" => { "error" => "Operação inválida." } }
    end

    def apply
      ActiveRecord::Base.transaction(requires_new: true) { ["applied", send(:"apply_#{@operation.kind}")] }
    rescue ActiveRecord::StaleObjectError, WorkOrders::AnswerChecklist::Conflict
      ["conflict", server_values]
    rescue Servora::RuleViolation, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, KeyError => e
      ["rejected", { "error" => e.message }]
    end

    def apply_time_entry
      payload = @operation.payload
      entry = TimeEntries::Record.new(work_order: @work_order, membership: @membership, source: "offline",
        started_at: Time.iso8601(payload.fetch("started_at")), ended_at: Time.iso8601(payload.fetch("ended_at")),
        notes: payload["notes"], client_operation_id: @operation.id).call
      { "time_entry_id" => entry.id, "minutes" => entry.minutes }
    end

    def apply_technical_report
      order = WorkOrders::UpdateTechnicalReport.new(work_order: @work_order, expected_version: @operation.version,
        diagnosis: @operation.payload["diagnosis"], solution: @operation.payload["solution"]).call
      { "version" => order.lock_version }
    end

    def apply_checklist
      item = checklist_item
      WorkOrders::AnswerChecklist.new(item:, response: @operation.payload["response"], actor: @membership,
        expected_version: @operation.version).call
      { "item_id" => item.id, "version" => item.reload.lock_version }
    end

    def checklist_item
      WorkOrderChecklistItem.where(work_order_id: @work_order.id).find(@operation.payload.fetch("item_id"))
    end

    def server_values
      case @operation.kind
      when "technical_report"
        order = WorkOrder.find(@work_order.id)
        { "diagnosis" => order.diagnosis, "solution" => order.solution, "version" => order.lock_version }
      when "checklist"
        item = checklist_item
        { "item_id" => item.id, "response" => item.response, "version" => item.lock_version }
      else {}
      end
    end

    def store(status, result)
      FieldOperation.create!(organization_id: @work_order.organization_id, operation_id: @operation.id, kind: @operation.kind,
        status:, result:, work_order: @work_order, membership: @membership).response
    end
  end
end
