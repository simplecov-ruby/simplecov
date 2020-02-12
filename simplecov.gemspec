# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)
require "simplecov/version"

Gem::Specification.new do |gem|
  gem.name        = "simplecov"
  gem.version     = SimpleCov::VERSION
  gem.platform    = Gem::Platform::RUBY
  gem.authors     = ["Christoph Olszowka"]
  gem.email       = ["christoph at olszowka de"]
  gem.homepage    = "https://github.com/colszowka/simplecov"
  gem.summary     = "Code coverage for Ruby"
  gem.description = %(Code coverage for Ruby with a powerful configuration library and automatic merging of coverage across test suites)
  gem.license     = "MIT"
  gem.metadata    = {
    "bug_tracker_uri"   => "https://github.com/colszowka/simplecov/issues",
    "changelog_uri"     => "https://github.com/colszowka/simplecov/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/simplecov/#{gem.version}",
    "mailing_list_uri"  => "https://groups.google.com/forum/#!forum/simplecov",
    "source_code_uri"   => "https://github.com/colszowka/simplecov/tree/v#{gem.version}"
  }

  gem.required_ruby_version = ">= 2.4.0"

  gem.add_dependency "docile", "~> 1.1"
  gem.add_dependency "simplecov-html", "~> 0.11"

  gem.files         = Dir["{lib}/**/*.*", "bin/*", "LICENSE", "*.md", "doc/*"]
  gem.require_paths = ["lib"]
end
