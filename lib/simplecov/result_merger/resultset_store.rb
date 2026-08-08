# frozen_string_literal: true

require "fileutils"
require "json"
require "monitor"
require_relative "../atomic_file"

module SimpleCov
  module ResultMerger
    # Reads and writes the persistent `.resultset.json` cache, including
    # file-lock synchronization between processes and atomic temp-file
    # renames so concurrent readers don't observe a truncated file.
    module ResultsetStore
      LOCK_MONITOR = Monitor.new
      private_constant :LOCK_MONITOR

    module_function

      def resultset_path
        File.join(SimpleCov.coverage_path, ".resultset.json")
      end

      def writelock_path
        File.join(SimpleCov.coverage_path, ".resultset.json.lock")
      end

      def write(resultset)
        AtomicFile.write(resultset_path, "#{JSON.pretty_generate(resultset)}\n")
      end

      # Serialize threads before taking the process-wide file lock. Nested
      # calls by the owning thread bypass flock so they cannot deadlock on a
      # second descriptor for the same lock file.
      def synchronize(&)
        return yield if LOCK_MONITOR.mon_owned?

        LOCK_MONITOR.synchronize { with_flock(&) }
      end

      def with_flock
        FileUtils.mkdir_p(SimpleCov.coverage_path)
        File.open(writelock_path, "w+") do |f|
          f.flock(File::LOCK_EX)
          yield
        end
      end
    end
  end
end
