# frozen_string_literal: true

module Authentication
  # Multi-factor enrollment policy for privileged roles (owner, admin, finance).
  #
  # Members get a grace period (MFA_ENROLLMENT_GRACE_DAYS, default 7) counted
  # from the moment they joined; afterwards the organization is blocked for
  # them until MFA is enabled.
  class MfaRequirement
    def self.grace_period
      Integer(ENV.fetch("MFA_ENROLLMENT_GRACE_DAYS", 7)).days
    end

    def initialize(membership:, user:, now: Time.current)
      @membership = membership
      @user = user
      @now = now
    end

    def required?
      @membership.privileged? && @membership.organization.mfa_required_for_privileged? && !@user.mfa_enabled?
    end

    def deadline
      @membership.created_at + self.class.grace_period
    end

    def blocking?
      required? && @now >= deadline
    end

    def pending?
      required? && !blocking?
    end
  end
end
