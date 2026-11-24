# frozen_string_literal: true

class TechnicianProfilePolicy < ApplicationPolicy
  def update? = can?(:schedule_manage)
end
