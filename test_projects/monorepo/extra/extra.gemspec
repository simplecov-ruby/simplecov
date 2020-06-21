# frozen_string_literal: true

Gem::Specification.new do |gem|
  gem.name        = "extra"
  gem.version     = "0.0.1"
  gem.authors     = ["Someone"]
  gem.email       = ["someonesemail"]
  gem.homepage    = "https://example.org"
  gem.summary     = "Extra stuff"
  gem.description = %(Extra stuff, really)
  gem.license     = "MIT"
  gem.add_dependency "base"
  gem.files       = ["lib/monorepo/extra.rb"]
end
