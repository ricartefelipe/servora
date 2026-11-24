# frozen_string_literal: true

# Rendered through config.exceptions_app. Messages are generic on purpose: they
# never reveal whether a resource exists in another organization.
class ErrorsController < ApplicationController
  ErrorPage = Data.define(:code, :title, :message)

  PAGES = {
    403 => ErrorPage.new(403, "Acesso negado", "Seu perfil não tem permissão para acessar este conteúdo."),
    404 => ErrorPage.new(404, "Página não encontrada", "O endereço não existe ou não está disponível para você."),
    406 => ErrorPage.new(406, "Navegador não suportado", "Atualize seu navegador para continuar."),
    422 => ErrorPage.new(422, "Não foi possível concluir", "A solicitação foi recusada. Recarregue a página e tente novamente."),
    429 => ErrorPage.new(429, "Muitas tentativas", "Aguarde alguns instantes antes de tentar novamente."),
    500 => ErrorPage.new(500, "Erro inesperado", "Registramos a falha. Tente novamente em instantes.")
  }.freeze

  layout "application"

  def show
    code = request.path.delete_prefix("/").to_i
    @error = PAGES.fetch(code, PAGES[500])
    respond_to do |format|
      format.html { render :show, status: @error.code }
      format.json { render json: { error: @error.title }, status: @error.code }
      format.any { head @error.code }
    end
  end
end
