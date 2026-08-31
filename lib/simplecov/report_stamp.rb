# frozen_string_literal: true

require "fileutils"

module SimpleCov
  # Touches coverage/.report_stamp whenever a report is formatted, no matter how
  # the run ends. The clobber-prevention backstop needs an on-disk signal that a
  # fresher report exists, and `.last_run.json` can't be it alone: that file is
  # only written after fully successful runs.
  module ReportStamp
    class << self
      def path
        File.join(SimpleCov.coverage_path, ".report_stamp")
      end

      # A read-only or vanished coverage dir must not crash reporting; the stamp
      # only powers the deferral heuristic.
      def touch
        FileUtils.touch(path)
      rescue SystemCallError
        nil
      end
    end
  end
end
