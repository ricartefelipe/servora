# frozen_string_literal: true

module Portal
  # Customers only see quotes of their own customer record and only the
  # frozen snapshot of sent versions (never drafts or internal costs).
  class QuotesController < BaseController
    include FileDelivery

    VISIBLE_STATUSES = %w[sent approved rejected expired converted].freeze

    rate_limit to: 10, within: 10.minutes, only: :decide, name: "portal-decision",
      with: -> { redirect_to portal_quotes_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

    def index
      @quotes = visible_quotes.includes(:current_version).order(created_at: :desc)
    end

    def show
      @quote = visible_quotes.includes(:current_version, versions: :decided_by_contact).find(params.expect(:id))
      @version = @quote.versions.to_a.rfind { |version| !version.draft? }
      @can_decide = @quote.sent? && @version&.id == @quote.current_version_id && current_contact.can_approve?
    end

    def decide
      quote = visible_quotes.find(params.expect(:id))
      decision = params.expect(decision: %i[outcome version_id content_digest note])
      Quotes::Decide.new(
        quote:, version_id: decision[:version_id], decision: decision[:outcome], digest: decision[:content_digest],
        contact: current_contact, channel: "portal", ip: request.remote_ip, user_agent: request.user_agent, note: decision[:note]
      ).call
      message = decision[:outcome] == "approved" ? "Proposta aprovada. Obrigado!" : "Recusa registrada."
      redirect_to portal_quote_path(quote), notice: message, status: :see_other
    rescue Servora::RuleViolation => e
      redirect_to portal_quote_path(quote), alert: e.message, status: :see_other
    end

    def pdf
      quote = visible_quotes.find(params.expect(:id))
      version = QuoteVersion.where(quote_id: quote.id).where.not(status: "draft")
        .find_by!(version_number: params.expect(:version))
      deliver_file(Documents::QuoteProposal.new(version).render, type: "application/pdf",
        filename: "proposta-#{quote.number}-v#{version.version_number}.pdf")
    end

    private

    def visible_quotes
      customer_scope(Quote).where(status: VISIBLE_STATUSES)
    end
  end
end
