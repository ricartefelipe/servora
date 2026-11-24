# frozen_string_literal: true

module Contracts
  States = StateMachines::Definition.new(
    draft: %i[active],
    active: %i[suspended ended],
    suspended: %i[active ended],
    ended: []
  )
end
