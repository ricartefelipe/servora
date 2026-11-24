# frozen_string_literal: true

module Quotes
  class RemoveItem
    include DraftEditing

    def initialize(item:)
      @item = item
      @version = item.quote_version
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        @version.lock!
        ensure_draft!(@version)
        @item.destroy!
        recalculate!(@version)
      end
    end
  end
end
