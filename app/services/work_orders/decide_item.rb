# frozen_string_literal: true

module WorkOrders
  # Records the customer's authorization (or refusal) of an additional item,
  # with the deciding contact, the channel and the registering member.
  class DecideItem
    class DecisionRefused < Servora::RuleViolation; end

    def initialize(item:, decision:, actor:, contact:, channel:, note: nil)
      @item = item
      @decision = decision.to_s
      @actor = actor
      @contact = contact
      @channel = channel.to_s
      @note = note.to_s.strip.presence
    end

    def call
      validate!
      @item.with_lock do
        raise DecisionRefused, "Este item já foi decidido." unless @item.pending?

        @item.update!(authorization_status: @decision, authorized_at: Time.current, authorized_by_membership: @actor,
          authorized_by_contact: @contact, authorization_channel: @channel, authorization_note: @note)
      end
      AuditEvent.record!(action: "work_order.item_#{@decision}", auditable: @item.work_order,
        changes: { item: @item.description, contact_id: @contact.id, channel: @channel })
      @item
    end

    private

    def validate!
      raise DecisionRefused, "Decisão inválida." unless %w[authorized rejected].include?(@decision)
      raise DecisionRefused, "Canal inválido." unless Quotes::Decide::CHANNELS.key?(@channel)
      return if @contact.customer_id == @item.work_order.customer_id && @contact.can_approve? && !@contact.archived?

      raise DecisionRefused, "Este contato não pode autorizar serviços deste cliente."
    end
  end
end
