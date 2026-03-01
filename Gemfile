source "https://rubygems.org"

gem "bootsnap", require: false
gem "importmap-rails"
gem "kamal", require: false
gem "pg", "~> 1.5"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rails", "~> 8.1.2"
gem "ruby-openai", "~> 8.3"
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "stimulus-rails"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "dotenv-rails"
  gem "pry"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "mocha"
  gem "selenium-webdriver"
end
