# frozen_string_literal: true

module Dashboards
  # Figures shown on the dashboard, each one filtered by the member's
  # permissions. Runs inside the request's tenant context.
  class Overview
    OnboardingStep = Data.define(:title, :description, :done, :path_helper)

    def initialize(membership:)
      @membership = membership
      @organization = membership.organization
    end

    def active_members_count
      @organization.memberships.active.count
    end

    def pending_invitations_count
      return nil unless @membership.can?(:members_view)

      @organization.invitations.pending.where("expires_at > ?", Time.current).count
    end

    def active_customers_count
      return nil unless @membership.can?(:customers_view)

      @organization.customers.active.count
    end

    # Equipment needing attention, grouped by operational status.
    def equipment_alerts
      return {} unless @membership.can?(:customers_view)

      @organization.equipment.active.where(operational_status: %w[attention inoperative]).group(:operational_status).count
    end

    # Work orders with a running deadline past or within the warning window.
    def sla_alerts(now: Time.current)
      return nil unless @membership.can?(:work_orders_view_all)

      { breached: WorkOrder.deadline_overdue(now).count, at_risk: WorkOrder.deadline_at_risk(now).count }
    end

    def onboarding_steps
      [
        OnboardingStep.new("Cadastre sua organização", "Dados da empresa, fuso horário e deslocamento padrão.", true,
          :edit_settings_path),
        OnboardingStep.new("Convide sua equipe", "Atendentes, coordenadores, técnicos e financeiro.", active_members_count > 1 ||
          @organization.invitations.exists?, :members_path),
        OnboardingStep.new("Cadastre clientes", "Locais de atendimento, contatos e equipamentos.",
          @organization.customers.exists?, :customers_path),
        OnboardingStep.new("Proteja sua conta", "Ative a verificação em duas etapas.", @membership.user.mfa_enabled?,
          :new_account_two_factor_path)
      ]
    end

    def show_onboarding?
      @membership.can?(:organization_manage) && !@organization.onboarding_completed?
    end
  end
end
