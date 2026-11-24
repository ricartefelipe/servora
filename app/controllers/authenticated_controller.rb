# frozen_string_literal: true

# Pages that require a signed-in user but no organization context
# (organization picker, account security, onboarding).
class AuthenticatedController < ApplicationController
  before_action :authenticate_user!

  layout "account"

  private

  def pundit_user
    PolicyContext.new(user: current_user, membership: nil)
  end
end
