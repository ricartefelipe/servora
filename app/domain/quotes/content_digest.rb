# frozen_string_literal: true

require "digest"
require "json"

module Quotes
  # SHA-256 of the canonical JSON of a version snapshot (keys sorted at every
  # level). Approval requests carry the digest of the content the customer saw;
  # a mismatch means the content changed and the approval is refused.
  module ContentDigest
    module_function

    def call(snapshot)
      Digest::SHA256.hexdigest(JSON.generate(canonical(snapshot)))
    end

    def canonical(value)
      case value
      when Hash then value.to_h { |key, val| [key.to_s, canonical(val)] }.sort.to_h
      when Array then value.map { |item| canonical(item) }
      when BigDecimal then value.to_s("F")
      when Date, Time then value.iso8601
      else value
      end
    end
  end
end
