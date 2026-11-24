# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Pessoa #{n}" }
    sequence(:email) { |n| "pessoa#{n}@servora.test" }
    password { "senha-segura-de-teste" }
    password_confirmation { password }
    confirmed_at { Time.current }

    trait :unconfirmed do
      confirmed_at { nil }
    end

    trait :with_mfa do
      otp_secret { User.generate_otp_secret }
      otp_required_for_login { true }
    end
  end

  factory :organization do
    sequence(:name) { |n| "Empresa #{n}" }
    segment { "hvac" }
    time_zone { "America/Sao_Paulo" }
    mfa_required_for_privileged { false }
  end

  factory :membership do
    organization
    user
    role { "owner" }

    Authorization::Permissions::ROLES.each do |role_name|
      trait role_name.to_sym do
        role { role_name }
      end
    end

    trait :deactivated do
      status { "deactivated" }
      deactivated_at { Time.current }
    end
  end

  factory :invitation do
    organization
    invited_by { association :membership, organization: }
    sequence(:email) { |n| "convidado#{n}@servora.test" }
    role { "technician" }
    token_digest { Invitation.digest(token) }
    expires_at { 7.days.from_now }

    transient do
      token { Invitation.generate_token }
    end
  end
end
