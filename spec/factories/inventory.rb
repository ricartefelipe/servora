# frozen_string_literal: true

FactoryBot.define do
  factory :warehouse do
    organization
    sequence(:name) { |n| "Depósito #{n}" }
    kind { "central" }

    trait :vehicle do
      kind { "vehicle" }
      custodian { association :membership, :technician, organization: }
    end
  end
end
