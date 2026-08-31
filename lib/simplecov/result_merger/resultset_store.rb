# frozen_string_literal: true

require "fileutils"
require "json"
require "monitor"
require_relative "../atomic_file"

module SimpleCov
  module ResultMerger
    module ResultsetStore
      LOCK_MONITOR = Monitor.new
      private_constant :LOCK_MONITOR

      extend self

      def resultset_path
        File.join(SimpleCov.coverage_path, ".resultset.json")
      end

      def writelock_path
        File.join(SimpleCov.coverage_path, ".resultset.json.lock")
      end

      # Compact JSON, not pretty-printed: this is a machine-read cache that every
      # parallel worker rewrites wholesale, and on a large project pretty printing
      # nearly doubles the bytes written, read back, and parsed on each of those
      # store-merge round trips.
      def write(resultset)
        AtomicFile.write(resultset_path, "#{JSON.generate(resultset)}\n")
      end

      # Threads are serialized before the process-wide file lock is taken. Nested
      # calls by the owning thread bypass flock so they cannot deadlock on a second
      # descriptor for the same lock file.
      def synchronize(&)
        return yield if LOCK_MONITOR.mon_owned?

        LOCK_MONITOR.synchronize { with_flock(&) }
      end

      def with_flock(&)
        FileUtils.mkdir_p(SimpleCov.coverage_path)
        holding_writelock(&)
      end

      def holding_writelock
        open_file(writelock_path, "w+") do |file|
          file.flock(File::LOCK_EX)
          yield
        end
      end

      # mutant:disable — Ruby 4.0 removed Kernel#open's leading-pipe
      # command mode, so no test can tell `File.open` from `open` here
      # any more. The explicit receiver is kept: on older rubies it is
      # what refuses to run a lock path as a command.
      def open_file(name, mode, &)
        File.open(name, mode, &)
      end
    end
  end
end
