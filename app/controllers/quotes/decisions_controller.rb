# frozen_string_literal: true

module Quotes
  # Internal registration of a decision communicated by the customer outside
  # the portal (phone, e-mail, in person). The registering member and the
  # deciding contact are both recorded.
  class DecisionsController < TenantController
    def create
      quote = policy_scope(tenant_relation(Quote)).includes(:current_version, :organization,
        :customer).find(params.expect(:quote_id))
      authorize quote, :register_decision?
      decide(quote, params.expect(decision: %i[outcome contact_id channel note content_digest version_id]))
      redirect_to quote_path(quote), notice: "Decisão do cliente registrada.", status: :see_other
    rescue Servora::RuleViolation => e
      redirect_to quote_path(quote), alert: e.message, status: :see_other
    end

    private

    def decide(quote, decision)
      contact = tenant_relation(CustomerContact).where(customer_id: quote.customer_id).find(decision[:contact_id])
      Quotes::Decide.new(
        quote:, version_id: decision[:version_id], decision: decision[:outcome], digest: decision[:content_digest], contact:,
        channel: decision[:channel], membership: current_membership, ip: request.remote_ip, user_agent: request.user_agent,
        note: decision[:note]
      ).call
    end
  end
end
