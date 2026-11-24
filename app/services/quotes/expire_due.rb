# frozen_string_literal: true

module Quotes
  # Marks sent versions past their validity as expired (runs daily per
  # organization; decisions are also refused on expired versions at once).
  class ExpireDue
    def initialize(organization:, today: nil)
      @organization = organization
      @today = today || Time.current.in_time_zone(organization.zone).to_date
    end

    def call
      due = @organization.quote_versions.where(status: "sent").where(valid_until: ...@today).includes(:quote)
      due.find_each.count do |version|
        ActiveRecord::Base.transaction(requires_new: true) do
          version.update!(status: Quotes::VersionStates.assert!(version.status, "expired"))
          version.quote.update!(status: "expired") if version.quote.current_version_id == version.id
          History.record!(version.quote, kind: "expired", version:)
        end
      end
    end
  end
end
