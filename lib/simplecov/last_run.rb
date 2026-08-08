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

        JSON.parse(json, symbolize_names: true)
      end

      def write(json)
        AtomicFile.write(last_run_path, "#{JSON.pretty_generate(json)}\n")
      end
    end
  end
end
