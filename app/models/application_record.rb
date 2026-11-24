# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # N+1 detection: lazily loading an association from a record that was loaded
  # as part of a collection raises in development and test and is logged in
  # production (see config/initializers/strict_loading.rb). Single-record lazy
  # loads remain allowed.
  self.strict_loading_by_default = true
  self.strict_loading_mode = :n_plus_one_only
end
