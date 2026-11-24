# frozen_string_literal: true

module WorkOrders
  # Work order lifecycle. Visits have their own machine (Visits::States): a
  # finished visit never completes the work order by itself.
  #
  #   open ─▶ awaiting_approval ─▶ approved ─▶ scheduled ─▶ in_progress ─▶ completed ─▶ reopened
  #                                   │            ▲   │         │  ▲
  #                                   └────────────┘   │         ▼  │
  #                                        waiting_parts / waiting_customer
  States = StateMachines::Definition.new(
    open: %i[awaiting_approval approved canceled],
    awaiting_approval: %i[approved canceled],
    approved: %i[scheduled in_progress canceled],
    scheduled: %i[approved in_progress waiting_customer canceled],
    in_progress: %i[scheduled waiting_parts waiting_customer completed canceled],
    waiting_parts: %i[scheduled in_progress canceled],
    waiting_customer: %i[scheduled in_progress canceled],
    completed: %i[reopened],
    reopened: %i[scheduled in_progress completed canceled],
    canceled: []
  )

  LABELS = {
    "open" => "Aberta", "awaiting_approval" => "Aguardando aprovação", "approved" => "Aprovada", "scheduled" => "Agendada",
    "in_progress" => "Em execução", "waiting_parts" => "Aguardando peças", "waiting_customer" => "Aguardando cliente",
    "completed" => "Concluída", "reopened" => "Reaberta", "canceled" => "Cancelada"
  }.freeze

  # States in which the customer is not causing the delay are "active" for
  # SLA purposes; waiting states pause the resolution clock.
  PAUSED_STATES = %w[waiting_parts waiting_customer].freeze
  TERMINAL_STATES = %w[completed canceled].freeze
end
