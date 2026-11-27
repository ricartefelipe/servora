# frozen_string_literal: true

module Quotes
  # Freezes the current draft version (snapshot + content digest), supersedes
  # the previous version and records "quote.sent" in the outbox so approvers
  # receive their portal link.
  class SendVersion
    include DraftEditing

    class NotSendable < Servora::RuleViolation; end

    def initialize(quote:, today: nil)
      @quote = quote
      @today = today
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @quote.lock!
        version = QuoteVersion.lock.includes(:items).find(@quote.current_version_id)
        ensure_draft!(version)
        validate!(version)
        supersede_previous!(version)
        freeze!(version)
        @quote.update!(status: "sent", approved_version_id: nil)
        History.record!(@quote, kind: "sent", version:)
        AuditEvent.record!(action: "quote.sent", auditable: @quote,
          changes: { version: version.version_number, total: version.total })
        Outbox::Publisher.publish!(event_type: "quote.sent", aggregate: version, dedup_key: "quote.sent:#{version.id}")
        version
      end
    end

    private

    def validate!(version)
      raise NotSendable, "Inclua ao menos um item antes de enviar." if version.items.empty?
      raise NotSendable, "A validade deve ser hoje ou uma data futura." if version.valid_until < today
      raise NotSendable, "O cliente está arquivado." if @quote.customer.archived?
    end

    def supersede_previous!(version)
      # The association is ordered by version number; batches go by id, so the order is dropped explicitly.
      @quote.versions.unscope(:order).where.not(id: version.id).where(status: %w[sent approved rejected expired])
        .find_each do |previous|
        previous.update!(status: Quotes::VersionStates.assert!(previous.status, "superseded"))
      end
    end

    def freeze!(version)
      snapshot = SnapshotBuilder.new(version).call
      version.update!(status: Quotes::VersionStates.assert!(version.status, "sent"), snapshot:,
        content_digest: ContentDigest.call(snapshot), sent_at: Time.current)
    end

    def today
      @today || Time.current.in_time_zone(@quote.organization.zone).to_date
    end
  end
end
