# frozen_string_literal: true

source "https://rubygems.org"

group :development do
  # rspec drives this suite, rake is its entry point, json_schemer checks the
  # JSON formatter against its schema, and test-unit backs the return-code
  # fixtures in spec/fixtures/frameworks.
  #
  # Cucumber and Minitest are only ever run from a sandbox fixture project,
  # so they belong to that project's Gemfile rather than this one. They sit
  # in optional groups there, because bundler materializes every gem a
  # Gemfile requires before running anything at all, and a plain dependency
  # would force every spec that drives the fixture to install them too.
  gem "json_schemer"
  gem "rake"
  gem "rspec"
  gem "test-unit"

  # Fans `rake spec` out across worker processes. The workers are plain
  # spawned subprocesses (no fork), so this works on every engine.
  gem "parallel_tests"

  # RBS's native extension fails to build on JRuby, so the type-checking
  # stack stays off there; JRuby runs `rake spec` only. The Rakefile's rbs
  # and steep tasks rescue the missing require with a warning.
  unless RUBY_ENGINE == "jruby"
    # Mutation testing (rake mutant). CRuby-only: mutant forks per
    # mutation, which the JVM engines cannot.
    gem "mutant", require: false
    gem "mutant-rspec", require: false

    gem "rbs", "~> 4.0.0"
    gem "steep", ">= 1.10", require: false
  end

  if RUBY_VERSION > "3.2"
    gem "rubocop"
    gem "rubocop-minitest"
    gem "rubocop-performance"
    gem "rubocop-rake"
    gem "rubocop-rspec"

    gem "standard", ">= 1.35.1"
    gem "standard-performance"
    gem "standard-rspec"
  end
end

group :benchmark do
  gem "benchmark-ips"
end

gemspec
