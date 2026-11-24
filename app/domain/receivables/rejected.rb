# frozen_string_literal: true

module Receivables
  # A financial operation that the receivable rules do not allow. Messages are
  # user-facing (pt-BR).
  class Rejected < StandardError; end
end
