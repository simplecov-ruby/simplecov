# frozen_string_literal: true

# Load default formatter gem
require "simplecov-html"
require "pathname"
require "simplecov/profiles/root_filter"
require "simplecov/profiles/test_frameworks"
require "simplecov/profiles/bundler_filter"
require "simplecov/profiles/rails"

# Default configuration
SimpleCov.configure do
  formatter SimpleCov::Formatter::HTMLFormatter
  load_profile "bundler_filter"
  # Exclude files outside of SimpleCov.root
  load_profile "root_filter"
end

# Gotta stash this a-s-a-p, see the CommandGuesser class and i.e. #110 for further info
SimpleCov::CommandGuesser.original_run_command = "#{$PROGRAM_NAME} #{ARGV.join(' ')}"

at_exit do # rubocop:disable Metrics/BlockLength
  # If we are in a different process than called start, don't interfere.
  next if SimpleCov.pid != Process.pid

  @exit_status = if $! # was an exception thrown?
                   # if it was a SystemExit, use the accompanying status
                   # otherwise set a non-zero status representing termination by
                   # some other exception (see github issue 41)
                   $!.is_a?(SystemExit) ? $!.status : SimpleCov::ExitCodes::EXCEPTION
                 else
                   # Store the exit status of the test run since it goes away
                   # after calling the at_exit proc...
                   SimpleCov::ExitCodes::SUCCESS
                 end

  SimpleCov.at_exit.call

  if SimpleCov.result? # Result has been computed
    covered_percent = SimpleCov.result.covered_percent.round(2)
    covered_percentages = SimpleCov.result.covered_percentages.map { |p| p.round(2) }

    if @exit_status == SimpleCov::ExitCodes::SUCCESS # No other errors
      if covered_percent < SimpleCov.minimum_coverage # rubocop:disable Metrics/BlockNesting
        $stderr.printf("Coverage (%.2f%%) is below the expected minimum coverage (%.2f%%).\n", covered_percent, SimpleCov.minimum_coverage)
        @exit_status = SimpleCov::ExitCodes::MINIMUM_COVERAGE
      elsif covered_percentages.any? { |p| p < SimpleCov.minimum_coverage_by_file } # rubocop:disable Metrics/BlockNesting
        $stderr.printf("File (%s) is only (%.2f%%) covered. This is below the expected minimum coverage per file of (%.2f%%).\n", SimpleCov.result.least_covered_file, covered_percentages.min, SimpleCov.minimum_coverage_by_file)
        @exit_status = SimpleCov::ExitCodes::MINIMUM_COVERAGE
      elsif (last_run = SimpleCov::LastRun.read) # rubocop:disable Metrics/BlockNesting
        coverage_diff = last_run["result"]["covered_percent"] - covered_percent
        if coverage_diff > SimpleCov.maximum_coverage_drop # rubocop:disable Metrics/BlockNesting
          $stderr.printf("Coverage has dropped by %.2f%% since the last time (maximum allowed: %.2f%%).\n", coverage_diff, SimpleCov.maximum_coverage_drop)
          @exit_status = SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
        end
      end

      if @exit_status == SimpleCov::ExitCodes::SUCCESS # rubocop:disable Metrics/BlockNesting
        SimpleCov::LastRun.write(:result => {:covered_percent => covered_percent})
      end
    end
  end

  # Force exit with stored status (see github issue #5)
  # unless it's nil or 0 (see github issue #281)
  Kernel.exit @exit_status if @exit_status && @exit_status > 0
end

# Autoload config from ~/.simplecov if present
require "simplecov/load_global_config"

# Autoload config from .simplecov if present
# Recurse upwards until we find .simplecov or reach the root directory

config_path = Pathname.new(SimpleCov.root)
loop do
  filename = config_path.join(".simplecov")
  if filename.exist?
    begin
      load filename
    rescue LoadError, StandardError
      $stderr.puts "Warning: Error occurred while trying to load #{filename}. " \
        "Error message: #{$!.message}"
    end
    break
  end
  config_path, = config_path.split
  break if config_path.root?
end
