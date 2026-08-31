# frozen_string_literal: true

require "parallel_tests"
require "parallel_tests/rspec/runtime_logger"

# Feeds `rake spec`'s runtime-based grouping (see .rspec_parallel and the
# Rakefile). parallel_tests' own RuntimeLogger records nothing here because
# spec/helper.rb scrubs TEST_ENV_NUMBER from the whole worker process (a
# child suite that inherits it defers its report to a "final" process that
# never runs). Restore the worker identity spec/helper.rb saved for the one
# call that writes the log, the same dance DogfoodReport does around
# ParallelTests.wait_for_other_processes_to_finish.
class RuntimeLogFormatter < ParallelTests::RSpec::RuntimeLogger
  RSpec::Core::Formatters.register(self, :example_group_started, :example_group_finished, :start_dump)

  def start_dump(*args)
    ENV["TEST_ENV_NUMBER"] = SPEC_PARALLEL_WORKER
    super
  ensure
    ENV.delete("TEST_ENV_NUMBER")
  end
end
