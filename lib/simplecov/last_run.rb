# frozen_string_literal: true

require "json"
require_relative "atomic_file"

module SimpleCov
  # Reads and writes coverage/.last_run.json — the previous run's coverage
  # percentages used by MaximumCoverageDropCheck.
  module LastRun
    class << self
      def last_run_path
        File.join(SimpleCov.coverage_path, ".last_run.json")
      end

      def read
        return nil unless File.exist?(last_run_path)

        json = File.read(last_run_path)
        return nil if json.strip.empty?

        parsed = JSON.parse(json, symbolize_names: true)
        # The maximum_coverage_drop check digs into a Hash, so anything
        # else in a corrupt or hand-edited file counts as "no previous
        # run" rather than crashing the at_exit hook.
        parsed.is_a?(Hash) ? parsed : invalid_last_run
      rescue JSON::ParserError
        invalid_last_run
      end

      def write(json)
        AtomicFile.write(last_run_path, "#{JSON.pretty_generate(json)}\n")
      end

    private

      def invalid_last_run
        warn "[SimpleCov]: Warning! Parsing JSON content of .last_run.json failed, ignoring the previous run"
        nil
      end
    end
  end
end
