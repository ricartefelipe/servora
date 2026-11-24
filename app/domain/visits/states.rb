# frozen_string_literal: true

module Visits
  # Visit lifecycle, independent from the work order: completing a visit only
  # records that the visit ended (the work order may need more visits).
  States = StateMachines::Definition.new(
    scheduled: %i[in_progress canceled no_show],
    in_progress: %i[completed],
    completed: [],
    canceled: [],
    no_show: []
  )

  LABELS = {
    "scheduled" => "Agendada", "in_progress" => "Em andamento", "completed" => "Realizada", "canceled" => "Cancelada",
    "no_show" => "Cliente ausente"
  }.freeze
end
