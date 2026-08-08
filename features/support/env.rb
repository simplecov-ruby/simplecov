# frozen_string_literal: true

# While you're here, handy tip for debugging: try to attach @announce-output
# @announce-command to the scenarios/features to see what's going on

require "bundler"
Bundler.setup
require "capybara/cucumber"
require "capybara/cuprite"
require "aruba/cucumber"
require "aruba/config/jruby" if RUBY_ENGINE == "jruby"
require "simplecov"

# Monkey-patching Capybara::DSL if Capybara::DSLRSpecProxyInstaller has no `extended` hook
unless Module.new.extend(RSpec::Matchers).extend(Capybara::DSL).singleton_class.ancestors.include?(Capybara::RSpecMatcherProxies)
  Capybara::DSL.extend(Module.new do
    def extended(base)
      base.extend(Capybara::RSpecMatcherProxies) if defined?(RSpec::Matchers) && base.is_a?(RSpec::Matchers)
      super
    end
  end)
end

# Under `parallel_cucumber` every worker gets its own Aruba sandbox
# (tmp/aruba1, tmp/aruba2, ...) so scenarios can't trample each other's
# copied projects; a serial run keeps the plain tmp/aruba. TEST_ENV_NUMBER
# is parallel_tests' convention: unset serially, "" for worker 1, "2"+ up.
ARUBA_WORKING_DIRECTORY = "tmp/aruba#{ENV.fetch('TEST_ENV_NUMBER', '')}".freeze

# Rack app for Capybara which returns the latest coverage report from Aruba temp project dir
coverage_dir = File.expand_path("../../#{ARUBA_WORKING_DIRECTORY}/project/coverage/", __dir__)

# Prevent the browser from caching the report between scenario visits
class NoCacheMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["cache-control"] = "no-store"
    [status, headers, body]
  end
end

Capybara.app = Rack::Builder.new do
  use NoCacheMiddleware
  use Rack::Static, urls: {"/" => "index.html"}, root: coverage_dir
  run Rack::Directory.new(coverage_dir)
end.to_app

# Explicit registration to raise Ferrum's default 10-second
# process_timeout: Chrome's first boot competes with the other parallel
# workers' boots and the scenarios' constant subprocess spawning for CPU
# on small CI runners, and losing that race fails one arbitrary scenario
# per worker. Boot happens once per worker and the timeout is a ceiling,
# so raising it doesn't slow the happy path. Window size is cuprite's
# own default, restated because registration replaces the stock driver.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1024, 768], process_timeout: 60)
end

Capybara.configure do |config|
  config.ignore_hidden_elements = false
  config.server = :webrick
  config.default_driver = :cuprite
end

Before("@branch_coverage") do
  skip_this_scenario unless SimpleCov.branch_coverage_supported?
end

Before("@method_coverage") do
  skip_this_scenario unless SimpleCov.method_coverage_supported?
end

Before("@process_fork") do
  # Process.fork is NotImplementedError in jruby
  skip_this_scenario if jruby?
end

Before("@no_jruby") do
  skip_this_scenario if jruby?
end

def jruby?
  defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
end

# parallel_cucumber marks each worker with parallel_tests' environment,
# and SimpleCov inside the spawned test projects reads the very same
# convention: an inherited TEST_ENV_NUMBER makes a child suite defer its
# report to a "final" parallel_tests process that never runs, so no
# report is generated and every scenario fails. The worker's marking is
# only for choosing the sandbox above; scrub it from the environment the
# scenarios' subprocesses see. Scenarios that exercise parallel_tests
# for real set the variables explicitly via `env ...` and are unaffected.
Before do
  %w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS PARALLEL_PID_FILE].each do |variable|
    delete_environment_variable(variable)
  end
end

Aruba.configure do |config|
  config.allow_absolute_paths = true
  config.working_directory = ARUBA_WORKING_DIRECTORY

  # Per-command ceiling. The 20-second default was tight enough that
  # cold-cache `bundle exec rspec` / `bundle exec parallel_rspec` /
  # `bundle exec rake test` invocations in the test_projects features
  # (old_version_json, parallel_tests, test_unit_without_simplecov)
  # would occasionally time out and fail before the work even
  # finished, even though the same scenarios passed instantly on a
  # warm cache. `--retry 3 --no-strict-flaky` masked the failures
  # but blew the suite's wall time up by 10x or more on cold runs.
  # 60 seconds accommodates first-bundle-activation latency on slow
  # CI runners without slowing the happy path (timeout is a ceiling).
  config.exit_timeout = RUBY_ENGINE == "jruby" ? 120 : 60
end
