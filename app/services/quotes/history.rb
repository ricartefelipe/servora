# frozen_string_literal: true

module Quotes
  module History
    module_function

    def record!(quote, kind:, version: nil, note: nil, metadata: {})
      quote.events.create!(organization_id: quote.organization_id, quote_version: version, kind:, note:,
        actor_type: Current.actor_type, actor_label: Current.actor_label, metadata:)
    end
  end
end
