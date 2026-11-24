# frozen_string_literal: true

module Servora
  # Failure that will not succeed on retry (invalid data, missing record,
  # rejected by a provider). Processing stops and the item is set aside.
  class PermanentError < StandardError; end
end
