# frozen_string_literal: true

# Forms rendered inside the shared modal (<dialog> in a Turbo Frame) submit to
# the top-level page: success redirects the whole page; validation errors are
# rendered back into the modal body with a Turbo Stream (422). Without Turbo
# the same actions render regular pages.
module ModalForms
  extend ActiveSupport::Concern

  private

  def render_invalid_form(partial:, template:, **locals)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("modal-body", partial:, locals:), status: :unprocessable_content
      end
      format.html { render template, status: :unprocessable_content }
    end
  end
end
