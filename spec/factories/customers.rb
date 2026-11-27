# frozen_string_literal: true

FactoryBot.define do
  factory :customer do
    organization
    kind { "company" }
    sequence(:name) { |n| "Cliente #{n} Ltda." }
    email { "contato@cliente.test" }

    trait :individual do
      kind { "individual" }
      sequence(:name) { |n| "Pessoa Física #{n}" }
    end
  end

  factory :service_location do
    customer
    organization { customer.organization }
    name { "Matriz" }
    street { "Av. Paulista" }
    number { "1000" }
    city { "São Paulo" }
    state { "SP" }
    postal_code { "01310100" }
  end

  factory :customer_contact do
    customer
    organization { customer.organization }
    sequence(:name) { |n| "Contato #{n}" }
    sequence(:email) { |n| "contato#{n}@cliente.test" }
    can_approve { true }
  end

  factory :equipment do
    transient do
      location { association :service_location }
    end

    service_location { location }
    customer { service_location.customer }
    organization { customer.organization }
    equipment_type { "Split hi-wall" }
    manufacturer { "Daikin" }
    model { "FTKP24Q5VL" }
    sequence(:serial_number) { |n| "SN#{n.to_s.rjust(6, "0")}" }
  end
end
