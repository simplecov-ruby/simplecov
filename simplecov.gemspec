# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

# Why oh why oh what is this?
# See the cuke that is setting this.
# Basically to really reproduce #877 we needed a gemspec that doesn't
# (indirectly) define a SimpleCov module... so this is the workaround.
version =
  if ENV["SIMPLECOV_NO_REQUIRE_VERSION"]
    ENV["SIMPLECOV_NO_REQUIRE_VERSION"]
  else
    require "simplecov/version"
    SimpleCov::VERSION
  end

Gem::Specification.new do |gem|
  gem.name        = "simplecov"
  gem.version     = version
  gem.platform    = Gem::Platform::RUBY
  gem.authors = [
    "Erik Berlin",
    "Benjamin Fleischer",
    "Akira Matsuda",
    "Christoph Olszowka",
    "Tobias Pfeiffer",
    "David Rodríguez",
    "Xavier Shay"
  ]
  gem.email = [
    "sferik@gmail.com",
    "github@benjaminfleischer.com",
    "ronnie@dio.jp",
    "christoph@olszowka.de",
    "pragtob@gmail.com",
    "deivid.rodriguez@gmail.com",
    "xavier@rhnh.net"
  ]
  gem.homepage    = "https://github.com/simplecov-ruby/simplecov"
  gem.summary     = "Code coverage for Ruby"
  gem.description = "Code coverage for Ruby with a powerful configuration library " \
                    "and automatic merging of coverage across test suites"
  gem.license     = "MIT"
  gem.metadata    = {
    "bug_tracker_uri" => "https://github.com/simplecov-ruby/simplecov/issues",
    "changelog_uri" => "https://github.com/simplecov-ruby/simplecov/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/simplecov/#{gem.version}",
    "mailing_list_uri" => "https://groups.google.com/forum/#!forum/simplecov",
    "source_code_uri" => "https://github.com/simplecov-ruby/simplecov/tree/v#{gem.version}",
    "rubygems_mfa_required" => "true"
  }

  gem.required_ruby_version = ">= 3.1"

  gem.files         = Dir["lib/**/*.*", "exe/*", "LICENSE", "CHANGELOG.md", "README.md", "doc/*"]
  gem.bindir        = "exe"
  gem.executables   = ["simplecov"]
  gem.require_paths = ["lib"]
end
