# frozen_string_literal: true

module Payments
  module Gateways
    module Errors
      class GatewayError < StandardError; end
      # The request did not reach the provider (connection refused, DNS, open
      # timeout): nothing was created, retrying is safe.
      class Unavailable < GatewayError; end
      # The provider may have processed the request (read timeout, 5xx): the
      # charge must be looked up by external reference before any new attempt.
      class AmbiguousResponse < GatewayError; end
      # Definitive refusal (validation, credentials): retrying will not help.
      class Rejected < GatewayError; end
    end
  end
end
