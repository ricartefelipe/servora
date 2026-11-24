# frozen_string_literal: true

# Headless policy: every active member may open the dashboard; the content is
# filtered by permission inside the dashboard query.
class DashboardPolicy < ApplicationPolicy
  def show? = membership.present?
end
