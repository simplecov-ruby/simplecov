# frozen_string_literal: true

# Borrowed and heavily adjusted from:
# https://github.com/metricfu/metric_fu/blob/master/spec/capture_warnings.rb
require "fileutils"

class FailOnWarnings
  def initialize
    @stderr_stream = StringIO.new
    @app_root = Dir.pwd
  end

  def collect_warnings
    $stderr = @stderr_stream
    $VERBOSE = true
  end

  def process_warnings
    lines = close_stream
    app_warnings, other_warnings = split_lines(lines)

    print_own_warnings(app_warnings) if app_warnings.any?
    write_other_warnings_to_tmp(other_warnings) if other_warnings.any?
    fail_script(app_warnings) if app_warnings.any?
  end

private

  def close_stream
    $stderr = STDERR

    @stderr_stream.rewind
    lines = @stderr_stream.read.split("\n")
    lines.uniq!
    @stderr_stream.close
    lines
  end

  # The :nocov: deprecation warning is fired by fixtures that legitimately
  # exercise the deprecated toggle. The "Coverage report generated for X
  # to /path/in/repo" status line is emitted by HTML/JSON formatters that
  # write into a temp dir under the app root and is on stderr by design.
  # Filter both so any future app-side deprecation or genuine warning
  # still fails the build.
  def split_lines(lines)
    nocov_deprecation_marker = "Replace with `# simplecov:disable` / `# simplecov:enable`"
    coverage_report_summary_marker = "Coverage report generated"
    lines.partition do |line|
      line.include?(@app_root) &&
        !line.include?(nocov_deprecation_marker) &&
        !line.start_with?(coverage_report_summary_marker)
    end
  end

  def print_own_warnings(app_warnings)
    puts ""
    puts ""
    puts <<~WARNINGS
      #{'-' * 30} app warnings: #{'-' * 30}
          #{app_warnings.join("\n")}
          #{'-' * 75}
    WARNINGS
  end

  def write_other_warnings_to_tmp(other_warnings)
    output_dir = File.join(@app_root, "tmp")
    FileUtils.mkdir_p(output_dir)
    # Suffixed with the parallel worker number (captured in spec/helper.rb
    # before the env scrub) so `rake spec`'s parallel workers don't
    # overwrite each other's captures.
    worker = defined?(SPEC_PARALLEL_WORKER) ? SPEC_PARALLEL_WORKER : nil
    filename = "warnings#{worker}.txt"
    File.write(File.join(output_dir, filename), other_warnings.join("\n") << "\n")
    puts
    puts "Non-app warnings written to tmp/#{filename}"
    puts
  end

  def fail_script(app_warnings)
    abort "Failing build due to app warnings: #{app_warnings.inspect}"
  end
end

# Under mutant the warning gate stands down: inserting a mutated method
# legitimately warns (a literal in a condition, a void-context `nil`),
# and the after(:suite) abort would kill the kill-fork before it reports
# its test result back, scoring the mutation alive no matter what the
# tests said.
unless defined?(Mutant)
  warning_collector = FailOnWarnings.new
  warning_collector.collect_warnings

  RSpec.configure do |config|
    config.after(:suite) do
      warning_collector.process_warnings
    end
  end
end
