# frozen_string_literal: true

module Portal
  # Rotates the grant token in a short transaction and e-mails the link
  # afterwards (no SMTP call inside the transaction).
  class DeliverGrant
    def initialize(organization_id:, grant_id:)
      @organization_id = organization_id
      @grant_id = grant_id
    end

    def call
      token, grant = rotate
      return false unless token

      PortalMailer.access(grant:, token:).deliver_now
      true
    end

    private

    def rotate
      Servora::Tenancy.with_organization(@organization_id) do
        grant = PortalAccessGrant.lock.includes(:organization, :quote, contact: :customer).find_by(id: @grant_id)
        next [nil, nil] unless grant&.usable?

        token = PortalAccessGrant.generate_token
        grant.update!(token_digest: PortalAccessGrant.digest(token))
        [token, grant]
      end
    end
  end
end
