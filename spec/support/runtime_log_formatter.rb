# frozen_string_literal: true

require "fileutils"
require "parallel_tests"
require "parallel_tests/rspec/runtime_logger"

# parallel_tests points every worker at one shared runtime log and opens it
# with "w", so the workers race to empty each other's results, and RSpec
# delivers `message` notifications to every formatter, so the "Run options"
# banner lands in it as well. Both leave a log that --group-by runtime reads as
# a suite with almost no files in it, which is worse than not grouping at all.
#
# Each worker writes its own file here instead, and `rake spec` merges them
# once the run is over.
class RuntimeLogFormatter < ParallelTests::RSpec::RuntimeLogger
  RSpec::Core::Formatters.register(self, :example_group_started, :example_group_finished, :start_dump)

  PARTIAL_DIR = "tmp/parallel_runtime"

  # Read at load time, which is before spec/helper.rb clears the variable so
  # that the suite under test cannot see it.
  WORKER = ENV.fetch("TEST_ENV_NUMBER", "")

  def initialize(*)
    FileUtils.mkdir_p(PARTIAL_DIR)
    super(File.join(PARTIAL_DIR, "#{WORKER.empty? ? 1 : WORKER}.log"))
  end

  # LoggerBase silences the rest of what it inherits from BaseTextFormatter,
  # but not this, and it is what writes the banner into the log.
  def message(*)
  end

  def start_dump(*)
    ENV["TEST_ENV_NUMBER"] = WORKER
    super
  ensure
    ENV.delete("TEST_ENV_NUMBER")
  end
end
