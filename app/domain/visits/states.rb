# frozen_string_literal: true

module Visits
  # Visit lifecycle, independent from the work order: completing a visit only
  # records that the visit ended (the work order may need more visits).
  #
  # "traveling" (em deslocamento) sits between scheduled and in progress and
  # is optional: a technician already on site starts the visit directly. Once
  # on the way the visit moves forward only (started, customer absent, or
  # canceled by the office); it never returns to scheduled, so the fact that
  # someone left for the site is never erased. Moving the visit to another
  # time means canceling it and scheduling a new one.
  States = StateMachines::Definition.new(
    scheduled: %i[traveling in_progress canceled no_show],
    traveling: %i[in_progress canceled no_show],
    in_progress: %i[completed],
    completed: [],
    canceled: [],
    no_show: []
  )

  LABELS = {
    "scheduled" => "Agendada", "traveling" => "Em deslocamento", "in_progress" => "Em andamento",
    "completed" => "Realizada", "canceled" => "Cancelada", "no_show" => "Cliente ausente"
  }.freeze

  # Visits that still hold the technician's time (listed as upcoming).
  OPEN = %w[scheduled traveling in_progress].freeze

  # Visits with the technician on the way or on site ("em campo").
  IN_FIELD = %w[traveling in_progress].freeze

  # Badge tone of each state (UiHelper::BADGE_TONES keys).
  TONES = {
    "scheduled" => :indigo, "traveling" => :ember, "in_progress" => :ember, "completed" => :success,
    "canceled" => :neutral, "no_show" => :neutral
  }.freeze
end
