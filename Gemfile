source "https://rubygems.org"

ruby file: ".ruby-version"

gem "rails", "~> 8.1.4"

# Persistence and web server
gem "pg", "~> 1.7"
gem "puma", "~> 8.1"

# Assets and front-end (no Node.js toolchain required)
gem "importmap-rails", "~> 2.2"
gem "propshaft", "~> 1.3"
gem "stimulus-rails", "~> 1.3"
gem "tailwindcss-rails", "~> 4.7"
gem "turbo-rails", "~> 2.0"

# Database-backed adapters for jobs, cable and cache
gem "solid_cable", "~> 4.1"
gem "solid_cache", "~> 1.0"
gem "solid_queue", "~> 1.7"

# Authentication and authorization
gem "devise", "~> 5.0"
gem "devise-two-factor", "~> 6.4"
gem "pundit", "~> 2.5"
gem "rqrcode", "~> 3.2"

# Documents
gem "prawn", "~> 2.5"

# Metrics exposition
gem "prometheus-client", "~> 5.0"

# Private object storage adapter for production attachments
gem "aws-sdk-s3", "~> 1.245", require: false

gem "bootsnap", "~> 1.26", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "brakeman", "~> 8.1", require: false
  gem "bundler-audit", "~> 0.9", require: false
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "factory_bot_rails", "~> 6.5"
  gem "rspec-rails", "~> 8.1"
  gem "rubocop", require: false
  gem "rubocop-capybara", require: false
  gem "rubocop-factory_bot", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rails", "~> 2.38", require: false
  gem "rubocop-rspec", "~> 3.10", require: false
  gem "rubocop-rspec_rails", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.20"
  gem "simplecov", "~> 1.3", require: false
  gem "webmock", "~> 3.40"
end
