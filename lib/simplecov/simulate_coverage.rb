# frozen_string_literal: true

module SimpleCov
  #
  # Responsible for producing file coverage metrics.
  #
  module SimulateCoverage
  module_function

    #
    # Simulate a file coverage report for a file that was tracked but never
    # required. Returns the same hash shape as `Coverage.result` (lines,
    # branches, methods).
    #
    # @return [Hash]
    #
    def call(absolute_path)
      lines = File.foreach(absolute_path)

      {
        "lines" => LinesClassifier.new.classify(lines),
        # we don't want to parse branches/methods ourselves...
        # requiring files can have side effects and we don't want to trigger that
        "branches" => {},
        "methods" => {}
      }
    end
  end
end
