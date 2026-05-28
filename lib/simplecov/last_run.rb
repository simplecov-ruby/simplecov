# frozen_string_literal: true

require "fileutils"
require "json"

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

      # Write to a process-private temp file, then atomically rename, so a
      # concurrent reader (e.g. another parallel-tests worker checking
      # MaximumCoverageDrop) never sees a half-written file.
      def write(json)
        FileUtils.mkdir_p(SimpleCov.coverage_path)
        temp_path = "#{last_run_path}.#{Process.pid}.tmp"
        File.open(temp_path, "w") { |f| f.puts JSON.pretty_generate(json) }
        File.rename(temp_path, last_run_path)
      end
    end
  end
end
