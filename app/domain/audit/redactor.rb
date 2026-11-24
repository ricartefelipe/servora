# frozen_string_literal: true

module Audit
  # Removes sensitive values before anything is written to the audit trail.
  # Keys are matched by name (case-insensitive, partial). Long strings are
  # truncated so that payloads are never stored in full.
  module Redactor
    SENSITIVE_KEY = /pass|token|secret|otp|api_?key|authorization|cookie|signature|card|cvv|cvc|digest|encrypted|session/i
    MASK = "[FILTRADO]"
    # Recorded instead of a secret to say that it was replaced; it carries no
    # secret material, so it is kept as is.
    CHANGED_MARKER = "[ALTERADA]"
    MAX_STRING = 500
    MAX_DEPTH = 5

    module_function

    def redact(value, depth = 0)
      return "[...]" if depth > MAX_DEPTH

      case value
      when Hash then redact_hash(value, depth)
      when Array then value.first(50).map { |item| redact(item, depth + 1) }
      else redact_scalar(value)
      end
    end

    def redact_scalar(value)
      case value
      when String then value.length > MAX_STRING ? "#{value[0, MAX_STRING]}…" : value
      when BigDecimal then value.to_s("F")
      else value
      end
    end

    def redact_hash(hash, depth)
      hash.each_with_object({}) do |(key, val), result|
        result[key.to_s] = if !SENSITIVE_KEY.match?(key.to_s) then redact(val, depth + 1)
                           elsif val == CHANGED_MARKER then CHANGED_MARKER
                           else MASK
                           end
      end
    end
  end
end
