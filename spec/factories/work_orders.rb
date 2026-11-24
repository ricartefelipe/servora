# frozen_string_literal: true

FactoryBot.define do
  factory :service_type do
    organization
    sequence(:name) { |n| "Manutenção preventiva #{n}" }

    transient do
      checklist do
        [["Medir pressão de sucção", "number", true], ["Limpar filtros", "check", true], ["Observações", "text", false]]
      end
    end

    after(:build) do |service_type, evaluator|
      evaluator.checklist.each_with_index do |(label, kind, required), index|
        service_type.checklist_items.build(organization: service_type.organization, label:, response_kind: kind, required:,
          position: index + 1)
      end
    end
  end
end
