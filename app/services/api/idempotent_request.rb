# frozen_string_literal: true

module Api
  # Stores the response of a write request under (credential, Idempotency-Key)
  # together with a digest of the request body. Replays return the stored
  # response; reusing the key with another body is refused. The work and the
  # stored response commit together.
  class IdempotentRequest
    class KeyReused < Servora::RuleViolation; end

    def initialize(credential:, key:, request_body:)
      @credential = credential
      @key = key
      @digest = OpenSSL::Digest::SHA256.hexdigest(JSON.generate(request_body.sort.to_h))
    end

    def call
      existing = replay
      return existing if existing

      ActiveRecord::Base.transaction(requires_new: true) do
        status, body = yield
        ApiIdempotencyKey.create!(organization_id: @credential.organization_id, api_credential: @credential, key: @key,
          request_digest: @digest, response_status: status, response_body: body)
        [status, body]
      end
    rescue ActiveRecord::RecordNotUnique
      replay || raise
    end

    private

    def replay
      stored = ApiIdempotencyKey.find_by(api_credential_id: @credential.id, key: @key)
      return nil unless stored
      raise KeyReused, "Idempotency-Key já utilizada com outro conteúdo." unless stored.request_digest == @digest

      [stored.response_status, stored.response_body]
    end
  end
end
