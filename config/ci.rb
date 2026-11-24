# Local verification equivalent to the GitHub Actions pipeline: `ruby bin/ci`.
CI.run do
  step "Estilo: RuboCop", "bundle exec rubocop"
  step "Segurança: Bundler Audit", "bundle exec bundler-audit check --update"
  step "Segurança: importmap", "ruby bin/importmap audit"
  step "Segurança: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Banco de testes", "RAILS_ENV=test ruby bin/db-prepare"
  step "Assets", "ruby bin/rails tailwindcss:build"
  step "Testes e cobertura", "ruby bin/test-all"
end
