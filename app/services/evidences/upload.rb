# frozen_string_literal: true

module Evidences
  # Stores an uploaded file as work order evidence after checking size and
  # content (file signature, not the declared type or extension). The blob is
  # created in the request's tenant context, so the database assigns and
  # enforces its organization.
  class Upload
    MAX_BYTES = 15 * 1024 * 1024
    MAX_PER_WORK_ORDER = 100

    class Rejected < Servora::RuleViolation; end

    def initialize(work_order:, file:, actor:, caption: nil)
      @work_order = work_order
      @file = file
      @actor = actor
      @caption = caption.to_s.squish.presence
    end

    def call
      content_type = validate!
      ActiveRecord::Base.transaction(requires_new: true) do
        blob = ActiveStorage::Blob.create_and_upload!(io: io, identify: false, content_type:,
          filename: Files::Signature.safe_filename(@file.original_filename, content_type))
        evidence = WorkOrderEvidence.create!(organization_id: @work_order.organization_id, work_order: @work_order,
          kind: Files::Signature::ALLOWED.fetch(content_type)[:kind], caption: @caption, content_type:,
          byte_size: blob.byte_size, original_filename: @file.original_filename.to_s.first(200), uploaded_by: @actor)
        evidence.file.attach(blob)
        AuditEvent.record!(action: "work_order.evidence_added", auditable: @work_order,
          changes: { filename: blob.filename.to_s, content_type:, byte_size: blob.byte_size })
        evidence
      end
    end

    private

    def io = @file.respond_to?(:tempfile) ? @file.tempfile.tap(&:rewind) : @file.tap(&:rewind)

    def validate!
      raise Rejected, "Selecione um arquivo." if @file.blank? || !@file.respond_to?(:read)

      size = @file.size
      raise Rejected, "O arquivo está vazio." if size.to_i.zero?
      raise Rejected, "O arquivo excede o limite de 15 MB." if size > MAX_BYTES
      if WorkOrderEvidence.where(work_order_id: @work_order.id).count >= MAX_PER_WORK_ORDER
        raise Rejected, "Limite de #{MAX_PER_WORK_ORDER} anexos por ordem atingido."
      end

      detect!
    end

    def detect!
      head = io.read(16)
      io.rewind
      Files::Signature.detect(head) || raise(Rejected, "Formato não aceito. Envie fotos (JPEG, PNG, WebP) ou PDF.")
    end
  end
end
