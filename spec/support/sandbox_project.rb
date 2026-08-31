# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"

module SandboxProject
  PROJECT_ROOT = File.expand_path("../..", __dir__)

  FRAMEWORK_CONFIG_DIRS = {
    rspec: "spec",
    test_unit: "test",
    cucumber: "features/support",
    minitest: "minitest"
  }.freeze

  CommandResult = Struct.new(:output, :exit_status, keyword_init: true) do
    def success?
      exit_status.zero?
    end
  end

  def sandbox_dir
    @sandbox_dir ||= File.join(sandbox_root, "project")
  end

  def sandbox_root
    File.join(PROJECT_ROOT, "tmp", "sandbox-#{Process.pid}")
  end

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

  attr_accessor :bundle_with

  def run_command_and_expect_success(command, env: {}, timeout: 60)
    result = run_command(command, env: env, timeout: timeout)
    return result if result.success?

    raise "Expected `#{command}` to succeed, exit status #{result.exit_status}:\n#{result.output}"
  end

  def sorted_rspec_command
    files = Dir.glob("spec/**/*_spec.rb", base: sandbox_dir).sort
    "bundle exec rspec #{files.join(' ')}"
  end

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

  def check_or_install_dependencies
    return if run_command("bundle check", timeout: 60).success?

    with_cross_process_install_lock do
      next if run_command("bundle check", timeout: 60).success?

      FileUtils.rm_f(File.join(sandbox_dir, "Gemfile.lock"))
      run_command_and_expect_success("bundle install", timeout: 180)
    end
  end

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

  def html_report_data(coverage_dir: "coverage")
    html = read_file("#{coverage_dir}/index.html")
    json = html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
    raise "No embedded coverage data found in #{coverage_dir}/index.html" unless json

    JSON.parse(json)
  end

  def resultset_json(coverage_dir: "coverage")
    JSON.parse(read_file("#{coverage_dir}/.resultset.json"))
  end

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

  def scrub_inherited_markers(env)
    {"TEST_ENV_NUMBER" => nil, "PARALLEL_TEST_GROUPS" => nil,
     "PARALLEL_PID_FILE" => nil, "PARALLEL_WORKERS" => nil,
     "FORCE_COLOR" => nil, "NO_COLOR" => nil}.merge(env)
  end

  def collect_command_result(command, stdout, wait_thread, timeout)
    output = +""
    reader = Thread.new { stdout.each_line { |line| output << line } }
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

  config.define_derived_metadata(sandbox: true) { |metadata| metadata[:mutant] = false }
  config.filter_run_excluding :sandbox if RUBY_ENGINE != "ruby" || Gem.win_platform?
  config.after(:suite) do
    FileUtils.rm_rf(File.join(SandboxProject::PROJECT_ROOT, "tmp", "sandbox-#{Process.pid}"))
  end
end
