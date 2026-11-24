# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_item do
    organization
    kind { "service" }
    sequence(:name) { |n| "Serviço #{n}" }
    unit { "un" }
    unit_price { BigDecimal("250.00") }
    unit_cost { BigDecimal("90.0000") }
    estimated_minutes { 60 }

    trait :part do
      kind { "part" }
      sequence(:name) { |n| "Peça #{n}" }
      unit_price { BigDecimal("80.00") }
      unit_cost { BigDecimal("35.5000") }
      tracks_inventory { true }
      estimated_minutes { nil }
    end
  end
end
