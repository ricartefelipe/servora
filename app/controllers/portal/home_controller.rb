# frozen_string_literal: true

module Portal
  class HomeController < BaseController
    def show
      @pending_quotes = customer_scope(Quote).where(status: "sent").includes(:current_version).order(created_at: :desc).limit(10)
    end
  end
end
