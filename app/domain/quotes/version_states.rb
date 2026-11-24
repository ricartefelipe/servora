# frozen_string_literal: true

module Quotes
  # Lifecycle of a quote version.
  #   draft → sent → approved | rejected | expired
  # A newer version supersedes any sent/decided one.
  VersionStates = StateMachines::Definition.new(
    draft: %i[sent],
    sent: %i[approved rejected expired superseded],
    approved: %i[superseded],
    rejected: %i[superseded],
    expired: %i[superseded]
  )
end
