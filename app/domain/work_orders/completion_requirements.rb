# frozen_string_literal: true

module WorkOrders
  # Pure check of what is still missing to complete a work order.
  module CompletionRequirements
    Checklist = Data.define(:label, :required, :response)

    module_function

    # Returns a list of human readable pending requirements (empty when ok).
    def missing(checklist:, diagnosis:, solution:, visits_in_progress:, pending_authorizations:)
      [
        checklist_problem(checklist),
        ("Registrar o diagnóstico" if blank?(diagnosis)),
        ("Registrar a solução aplicada" if blank?(solution)),
        ("Finalizar a visita em deslocamento ou em andamento" if visits_in_progress.positive?),
        ("Decidir os serviços adicionais pendentes de autorização" if pending_authorizations.positive?)
      ].compact
    end

    def checklist_problem(checklist)
      unanswered = checklist.select { |item| item.required && blank?(item.response) }
      return nil if unanswered.empty?

      "Responder os itens obrigatórios do checklist: #{unanswered.map(&:label).join(", ")}"
    end

    def blank?(value) = value.to_s.strip.empty?
  end
end
