# frozen_string_literal: true

# Management reports (headless). Financial figures need :finance_view;
# costs and margins need :costs_view, as everywhere else.
class ReportPolicy < ApplicationPolicy
  def show? = can?(:reports_view)
  def finance? = show? && can?(:finance_view)
  def materials? = show? && can?(:inventory_view)
  def costs? = can?(:costs_view)
end
