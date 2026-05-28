# frozen_string_literal: true

require "fileutils"
require "json"

module SimpleCov
  module ResultMerger
    # Reads and writes the persistent `.resultset.json` cache, including
    # file-lock synchronization between processes and atomic temp-file
    # renames so concurrent readers don't observe a truncated file.
    module ResultsetStore
    module_function

      def resultset_path
        File.join(SimpleCov.coverage_path, ".resultset.json")
      end

      def writelock_path
        File.join(SimpleCov.coverage_path, ".resultset.json.lock")
      end

      def write(resultset)
        FileUtils.mkdir_p(SimpleCov.coverage_path)
        temp_path = "#{resultset_path}.#{Process.pid}.tmp"
        File.open(temp_path, "w") { |f| f.puts JSON.pretty_generate(resultset) }
        File.rename(temp_path, resultset_path)
      end

      # Ensure only one process is reading or writing the resultset at
      # any given time. Reentrant: the lock is acquired once per outer
      # call no matter how deeply nested.
      def synchronize(&)
        return yield if @locked

        @locked = true
        with_flock(&)
      ensure
        @locked = false
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
