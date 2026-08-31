# frozen_string_literal: true

require "parallel_tests"
require "parallel_tests/rspec/runtime_logger"

class RuntimeLogFormatter < ParallelTests::RSpec::RuntimeLogger
  RSpec::Core::Formatters.register(self, :example_group_started, :example_group_finished, :start_dump)

  def start_dump(*args)
    ENV["TEST_ENV_NUMBER"] = SPEC_PARALLEL_WORKER
    super
  ensure
    ENV.delete("TEST_ENV_NUMBER")
  end
end
