# frozen_string_literal: true

module Servora
  # Base class for business rule violations raised by use cases. The message is
  # written for end users (Portuguese) and is safe to display.
  class RuleViolation < StandardError; end
end
