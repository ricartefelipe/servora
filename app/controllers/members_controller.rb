# frozen_string_literal: true

class MembersController < TenantController
  before_action :load_membership, only: %i[edit update deactivate reactivate]

  def index
    authorize Membership
    @memberships = policy_scope(current_organization.memberships).includes(:user).ordered
    @invitations = policy_scope(current_organization.invitations).pending.includes(invited_by: :user).recent_first
    @invitation = current_organization.invitations.new(role: "technician")
  end

  def edit; end

  def update
    Memberships::Update.new(membership: @membership, attributes: membership_params).call
    redirect_to members_path, notice: "Dados de #{@membership.user.name} atualizados."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  rescue Servora::RuleViolation => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_content
  end

  def deactivate
    Memberships::Deactivate.new(membership: @membership, actor: current_user).call
    redirect_to members_path, notice: "Acesso de #{@membership.user.name} desativado."
  rescue Servora::RuleViolation => e
    redirect_to members_path, alert: e.message
  end

  def reactivate
    Memberships::Reactivate.new(membership: @membership).call
    redirect_to members_path, notice: "Acesso de #{@membership.user.name} reativado."
  end

  private

  def load_membership
    @membership = tenant_relation(Membership).includes(:user, :organization).find(params.expect(:id))
    authorize @membership, :"#{action_name == "edit" ? "update" : action_name}?"
  end

  def membership_params
    permitted = policy(@membership).permitted_attributes
    attributes = params.expect(membership: permitted)
    if attributes[:role].present? && policy(@membership).assignable_roles.exclude?(attributes[:role])
      raise Pundit::NotAuthorizedError
    end

    attributes
  end
end
