# frozen_string_literal: true

module Servora
  # Failure expected to succeed on retry (timeouts, unavailable dependency).
  class TransientError < StandardError; end
end
