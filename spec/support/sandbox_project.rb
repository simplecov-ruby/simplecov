# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

# Drives a copy of a test_projects fixture in an isolated sandbox,
# mirroring what the cucumber + aruba suite used to do: copy the project,
# inject a simplecov config, run its test suite in a subprocess, and
# assert on the output and the emitted report artifacts.
#
# The sandbox project lives at tmp/sandbox-<pid>/project — exactly
# three directory levels below the repository root, the same depth the
# aruba sandbox (tmp/aruba/project) used — because the fixture Gemfiles
# reference the simplecov gem by relative path (`path: "../../.."`, with
# a `"../.."` fallback for in-place development).
#
module SandboxProject
  PROJECT_ROOT = File.expand_path("../..", __dir__)

  # The test-framework config file each fixture project loads (see e.g.
  # test_projects/faked_project/spec/spec_helper.rb).
  FRAMEWORK_CONFIG_DIRS = {
    rspec: "spec",
    test_unit: "test",
    cucumber: "features/support",
    minitest: "minitest"
  }.freeze

  # Result of a sandboxed command: everything the aruba assertions used.
  CommandResult = Struct.new(:output, :exit_status, keyword_init: true) do
    def success?
      exit_status.zero?
    end
  end

  # Per-process so concurrent rspec processes can't trample each other's
  # sandboxes; cleaned up in the after(:suite) hook below.
  def sandbox_dir
    @sandbox_dir ||= File.join(sandbox_root, "project")
  end

  def sandbox_root
    File.join(PROJECT_ROOT, "tmp", "sandbox-#{Process.pid}")
  end

  # Copies test_projects/<name> into a fresh sandbox. `subdir` selects a
  # nested project (e.g. "rails/rspec_rails"). `gemfile_from` overlays
  # another fixture's Gemfile for fixtures that only vary in gems.
  def setup_project(name, gemfile_from: nil)
    source = File.join(PROJECT_ROOT, "test_projects", name)
    @gemfile_fixture = gemfile_from || name
    FileUtils.rm_rf(sandbox_root)
    FileUtils.mkdir_p(sandbox_root)
    FileUtils.cp_r(source, sandbox_dir)
    scrub_untracked_coverage_dirs(source)

    return unless gemfile_from

    gemfile_source = File.join(PROJECT_ROOT, "test_projects", gemfile_from)
    FileUtils.cp(Dir.glob("#{gemfile_source}/Gemfile*"), sandbox_dir)
  end

  # Writes the simplecov config file the fixture's test helper loads.
  def configure_simplecov(framework, body)
    write_file(File.join(FRAMEWORK_CONFIG_DIRS.fetch(framework), "simplecov_config.rb"), body)
  end

  def write_file(relative_path, content)
    path = File.join(sandbox_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read_file(relative_path)
    File.read(File.join(sandbox_dir, relative_path))
  end

  def file_exist?(relative_path)
    File.exist?(File.join(sandbox_dir, relative_path))
  end

  # Runs a command inside the sandbox with a fresh Bundler activation. A
  # copied Gemfile must lead the definition, but the subprocess still reuses
  # the host bundle path and excluded groups (CI keeps benchmark gems out of
  # that cache). Fixtures without a Gemfile intentionally use the root one.
  # The parallel_tests marker variables are scrubbed for the same reason the
  # cucumber suite scrubbed them: an inherited TEST_ENV_NUMBER makes a child
  # suite defer its report to a "final" process that never runs. The colour
  # overrides go too, so a child's output is plain whatever the terminal
  # running the suite prefers.
  def run_command(command, env: {}, timeout: 60)
    command_env = sandbox_command_environment(env)
    @last_command = Open3.popen2e(
      command_env, command, chdir: sandbox_dir, unsetenv_others: true
    ) do |stdin, stdout, wait_thread|
      stdin.close
      collect_command_result(command, stdout, wait_thread, timeout)
    end
  end

  attr_reader :last_command

  # Fixtures park their rarely-exercised frameworks in optional Gemfile
  # groups, which bundler leaves out of the bundle unless asked for them, so
  # the specs that never touch those frameworks never have to install them.
  # A spec that does need one names the group here before it installs, and
  # every command it runs in the sandbox opts that group in.
  attr_accessor :bundle_with

  def run_command_and_expect_success(command, env: {}, timeout: 60)
    result = run_command(command, env: env, timeout: timeout)
    return result if result.success?

    raise "Expected `#{command}` to succeed, exit status #{result.exit_status}:\n#{result.output}"
  end

  # `bundle exec rspec spec` with the spec files in stable alphabetical
  # order: rspec randomizes file order, but coverage never includes the
  # first-loaded spec file, so reports that include spec files need a
  # deterministic first file.
  def sorted_rspec_command
    files = Dir.glob("spec/**/*_spec.rb", base: sandbox_dir).sort
    "bundle exec rspec #{files.join(' ')}"
  end

  # A bundle that has satisfied `bundle check` once cannot stop being
  # satisfied mid-suite, and no sandbox example rewrites its copied
  # Gemfile, so one verification per (fixture Gemfile, opted-in groups)
  # pair covers every later example that uses the same pair. Without
  # the cache each example pays a full Bundler boot just to re-ask.
  #
  # The cache stores the lockfile the verification ended with, and a
  # hit writes it into the example's fresh copy. Satisfying a shipped
  # lock that pins gems the running Ruby cannot install re-resolves it
  # fresh (see below) in the verifying example's copy alone, so later
  # copies ship the original lock again: handing them the resolved
  # lock is what keeps their `bundle exec` off gem versions that were
  # never installed.
  def install_dependencies
    key = [@gemfile_fixture, bundle_with]
    if (lockfile = VERIFIED_BUNDLES[key])
      return write_file("Gemfile.lock", lockfile)
    end

    check_or_install_dependencies
    VERIFIED_BUNDLES[key] = read_file("Gemfile.lock")
  end

  # rubocop:disable-next Style/MutableConstant -- the cache fills in as fixtures verify
  VERIFIED_BUNDLES = {}

  # `bundle check` answers in a fraction of a full resolve when the
  # shipped lockfile is already satisfied; anything else drops the lock
  # and resolves fresh. Installs are serialized across concurrent rspec
  # processes because rubygems' native-extension builds are not
  # concurrency-safe: two simultaneous installs of the same gem compile
  # in the same ext directory and the loser dies mid-make.
  def check_or_install_dependencies
    return if run_command("bundle check", timeout: 60).success?

    with_cross_process_install_lock do
      next if run_command("bundle check", timeout: 60).success?

      FileUtils.rm_f(File.join(sandbox_dir, "Gemfile.lock"))
      run_command_and_expect_success("bundle install", timeout: 180)
    end
  end

  # --- report assertions -------------------------------------------------

  def expect_coverage_report_generated(result, coverage_dir: "coverage")
    expect(result.output).to include("Coverage report generated")
    expect(file_exist?("#{coverage_dir}/index.html")).to be(true), "expected #{coverage_dir}/index.html to exist"
    expect(file_exist?("#{coverage_dir}/.resultset.json")).to be(true),
                                                              "expected #{coverage_dir}/.resultset.json to exist"
  end

  def expect_no_coverage_report(result, coverage_dir: "coverage")
    expect(result.output).not_to include("Coverage report generated")
    expect(file_exist?("#{coverage_dir}/index.html")).to be(false), "expected no #{coverage_dir}/index.html"
    expect(file_exist?("#{coverage_dir}/.resultset.json")).to be(false), "expected no #{coverage_dir}/.resultset.json"
  end

  def coverage_json(coverage_dir: "coverage")
    JSON.parse(read_file("#{coverage_dir}/coverage.json"))
  end

  # The data payload embedded in the generated HTML report — everything
  # the browser-based cucumber assertions could see, without a browser.
  # The `;</script>` terminator is unambiguous because the formatter
  # escapes every `<` in the JSON (see HTMLFormatter#data_script).
  def html_report_data(coverage_dir: "coverage")
    html = read_file("#{coverage_dir}/index.html")
    json = html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
    raise "No embedded coverage data found in #{coverage_dir}/index.html" unless json

    JSON.parse(json)
  end

  def resultset_json(coverage_dir: "coverage")
    JSON.parse(read_file("#{coverage_dir}/.resultset.json"))
  end

  # The overall line-coverage percent and the per-file percents from
  # coverage.json, floored to two decimals exactly the way the HTML
  # viewer displays them (see formatPercent in html_frontend/src/format.ts).
  def displayed_percent(percent)
    (percent * 100).floor / 100.0
  end

  def reported_total_percent(json = coverage_json, criterion: "lines")
    displayed_percent(json.fetch("total").fetch(criterion).fetch("percent"))
  end

  def reported_file_percents(json = coverage_json, criterion: "lines")
    json.fetch("coverage").to_h do |file, data|
      [file, displayed_percent(data.fetch("#{criterion}_covered_percent"))]
    end
  end

  def reported_group(json, name)
    json.fetch("groups").fetch(name)
  end

  # Appended to injected configs so data assertions can read
  # coverage.json while the HTML report keeps being exercised too.
  JSON_ALONGSIDE_HTML = <<~RUBY
    SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter]
  RUBY

private

  def sandbox_command_environment(overrides)
    Bundler.unbundled_env
           .merge(host_bundle_settings)
           .merge("BUNDLE_WITH" => bundle_with)
           .merge(scrub_inherited_markers(overrides))
           .merge("BUNDLE_GEMFILE" => sandbox_gemfile)
  end

  def host_bundle_settings
    {
      "BUNDLE_PATH" => host_bundle_path,
      "BUNDLE_WITHOUT" => host_bundle_without
    }.compact
  end

  def host_bundle_path
    path = Bundler.settings[:path]
    File.expand_path(path, PROJECT_ROOT) if path
  end

  def host_bundle_without
    groups = Array(Bundler.settings[:without]).map(&:to_s)
    groups.join(":") unless groups.empty?
  end

  def sandbox_gemfile
    copied = File.join(sandbox_dir, "Gemfile")
    File.file?(copied) ? copied : File.join(PROJECT_ROOT, "Gemfile")
  end

  # PARALLEL_WORKERS is Rails' own knob: `ActiveSupport::TestCase.parallelize`
  # lets it override the `workers:` argument outright, so an exported value
  # would silently re-shape the fixtures that pin a worker count.
  # The colour overrides go with them, and have to be scrubbed here as
  # well as in the spec helper: `Bundler.unbundled_env` rebuilds the
  # environment from the snapshot Bundler took before the helper ran, so
  # a FORCE_COLOR the helper deleted comes back for the child.
  def scrub_inherited_markers(env)
    {"TEST_ENV_NUMBER" => nil, "PARALLEL_TEST_GROUPS" => nil,
     "PARALLEL_PID_FILE" => nil, "PARALLEL_WORKERS" => nil,
     "FORCE_COLOR" => nil, "NO_COLOR" => nil}.merge(env)
  end

  def collect_command_result(command, stdout, wait_thread, timeout)
    output = +""
    reader = Thread.new { stdout.each_line { |line| output << line } }
    # Unwinding from the timeout below closes the stream this thread is
    # blocked on, which raises IOError inside it. That is expected teardown
    # rather than a fault worth announcing, and left to report itself it
    # reaches the suite's warning capture and fails the build with a stack
    # trace instead of the timeout message that explains what went wrong.
    reader.report_on_exception = false
    unless wait_thread.join(timeout)
      Process.kill("KILL", wait_thread.pid)
      reader.kill
      raise "Command `#{command}` timed out after #{timeout}s. Output so far:\n#{output}"
    end
    reader.join
    CommandResult.new(output: output, exit_status: wait_thread.value.exitstatus)
  end

  def with_cross_process_install_lock
    path = File.join(PROJECT_ROOT, "tmp", "sandbox-bundle-install.lock")
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, File::CREAT | File::RDWR) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    end
  end

  # Coverage output is gitignored, so an ad-hoc local run can leave a
  # stray coverage/ dir in the fixture source that cp_r drags into the
  # fresh sandbox, breaking "no coverage report" assertions. Drop copied
  # coverage dirs the source doesn't track (the old_coverage_json
  # project ships a tracked coverage/ fixture, which stays).
  def scrub_untracked_coverage_dirs(source)
    Dir.glob("**/coverage", base: sandbox_dir).each do |copied|
      tracked = system("git", "-C", source, "ls-files", "--error-unmatch", copied,
                       out: File::NULL, err: File::NULL)
      FileUtils.rm_rf(File.join(sandbox_dir, copied)) unless tracked
    end
  end
end

RSpec.configure do |config|
  config.include SandboxProject, :sandbox

  # A sandbox example proves the library works when a real project runs
  # it, which is worth having and is not something mutation analysis can
  # use: the example asserts on a child process, and mutant mutates the
  # parent in memory, so the child loads the file from disk unmutated
  # and the example passes whatever was done to the code. Left in a
  # subject's test pool it is pure cost, and an expensive one, since
  # each example spawns a bundler and a test run.
  config.define_derived_metadata(sandbox: true) { |metadata| metadata[:mutant] = false }
  # The sandbox suite keeps the platform envelope of the cucumber feature
  # suite it replaced, which only ever ran on MRI Linux/macOS: alternative
  # engines and Windows run the unit specs alone.
  config.filter_run_excluding :sandbox if RUBY_ENGINE != "ruby" || Gem.win_platform?
  config.after(:suite) do
    FileUtils.rm_rf(File.join(SandboxProject::PROJECT_ROOT, "tmp", "sandbox-#{Process.pid}"))
  end
end
