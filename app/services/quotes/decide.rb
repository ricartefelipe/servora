# frozen_string_literal: true

module Quotes
  # Records the customer's approval or rejection of a specific version.
  #
  # Evidence stored: version and its content digest (the customer must confirm
  # the exact content shown), deciding contact, registering member (internal
  # channel), channel, timestamp, IP and user agent. This is an electronic
  # confirmation, not a certified signature.
  class Decide
    DECISIONS = %w[approved rejected].freeze
    CHANNELS = { "portal" => "Portal do cliente", "phone" => "Telefone", "email" => "E-mail",
                 "whatsapp" => "Aplicativo de mensagens", "in_person" => "Presencial" }.freeze

    class DecisionRefused < Servora::RuleViolation; end

    def initialize(quote:, version_id:, decision:, digest:, contact:, channel:, membership: nil, ip: nil, user_agent: nil,
                   note: nil, now: Time.current)
      @quote = quote
      @version_id = version_id
      @decision = decision.to_s
      @digest = digest.to_s
      @contact = contact
      @channel = channel.to_s
      @membership = membership
      @evidence = { ip:, user_agent: user_agent.to_s.first(255), note: note.to_s.strip.first(1000).presence }
      @now = now
    end

    def call
      validate_request!
      ActiveRecord::Base.transaction(requires_new: true) do
        @quote.lock!
        version = @quote.versions.lock.find(@version_id)
        ensure_decidable!(version)
        record!(version)
        version
      end
    end

    private

    def validate_request!
      refuse!("Decisão inválida.") unless DECISIONS.include?(@decision)
      refuse!("Canal inválido.") unless CHANNELS.key?(@channel)
      refuse!("Informe quem aprovou pelo cliente.") unless @contact
      validate_evidence!
    end

    def validate_evidence!
      refuse!("Registros internos exigem o responsável pelo registro.") if @channel != "portal" && @membership.nil?
      refuse!("Descreva o motivo da recusa.") if @decision == "rejected" && @evidence[:note].blank?
    end

    def ensure_decidable!(version)
      refuse!("Esta versão não é a vigente do orçamento.") unless @quote.current_version_id == version.id
      refuse!("Esta versão não está aguardando decisão.") unless version.sent?
      refuse!("A validade desta versão terminou em #{I18n.l(version.valid_until)}.") if version.expired_on?(today)
      refuse!("O conteúdo foi alterado. Recarregue a proposta.") unless ActiveSupport::SecurityUtils.secure_compare(
        version.content_digest.to_s, @digest
      )
      refuse!("Este contato não pode aprovar orçamentos deste cliente.") unless contact_allowed?
    end

    def contact_allowed?
      @contact.customer_id == @quote.customer_id && @contact.can_approve? && !@contact.archived?
    end

    def record!(version)
      version.update!(status: Quotes::VersionStates.assert!(version.status, @decision), decided_at: @now,
        decision_channel: @channel, decided_by_contact: @contact, decided_by_membership: @membership,
        decision_ip: @evidence[:ip], decision_user_agent: @evidence[:user_agent], decision_note: @evidence[:note])
      @quote.update!(status: @decision, approved_version_id: (version.id if @decision == "approved"))
      History.record!(@quote, kind: @decision, version:, note: @evidence[:note],
        metadata: { channel: @channel, contact: @contact.name, digest: version.content_digest })
      AuditEvent.record!(action: "quote.#{@decision}", auditable: @quote,
        changes: { version: version.version_number, channel: @channel, contact_id: @contact.id })
      Outbox::Publisher.publish!(event_type: "quote.#{@decision}", aggregate: version, dedup_key: "quote.decided:#{version.id}")
    end

    def refuse!(message) = raise(DecisionRefused, message)
    def today = @now.in_time_zone(@quote.organization.zone).to_date
  end
end
