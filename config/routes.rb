Rails.application.routes.draw do
  get "up" => "health#live", as: :liveness
  get "ready" => "health#ready", as: :readiness

  %w[403 404 406 422 429 500].each do |code|
    match code, to: "errors#show", via: :all, code: code
  end

  root "pages#home"
end
