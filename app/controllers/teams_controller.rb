# frozen_string_literal: true

class TeamsController < TenantController
  def create
    authorize Visit, :create?
    team_params = params.expect(team: [:name, { membership_ids: [] }])
    ActiveRecord::Base.transaction(requires_new: true) { build_team(team_params) }
    redirect_to technicians_path, notice: "Equipe criada.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to technicians_path, alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def destroy
    authorize Visit, :create?
    tenant_relation(Team).find(params.expect(:id)).update!(active: false)
    redirect_to technicians_path, notice: "Equipe desativada.", status: :see_other
  end

  private

  def build_team(team_params)
    team = current_organization.teams.create!(name: team_params[:name])
    tenant_relation(Membership).technicians.where(id: Array(team_params[:membership_ids])).find_each do |membership|
      team.team_members.create!(organization: current_organization, membership:)
    end
  end
end
