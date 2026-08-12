# frozen_string_literal: true

require "fileutils"
require "timeout"

module ParallelWorkerProbe
  MARKER_DIR = "tmp/worker_pids"

  # The markers are also how the spec proves the two tests ran on different
  # workers, and the wait below is what forces them apart. A set left over
  # from an earlier run satisfies that wait before either test starts, so
  # clear it in the parent process before any worker is forked. The tree is
  # gitignored, which is exactly why a stale copy can survive: the sandbox
  # stages fixtures by copying the directory, not by asking git what's in it.
  def self.reset!
    FileUtils.rm_rf(Rails.root.join(MARKER_DIR))
  end

  def wait_for_other_worker(name)
    marker_dir = Rails.root.join(MARKER_DIR)
    FileUtils.mkdir_p(marker_dir)
    File.write(marker_dir.join(name), Process.pid)

    Timeout.timeout(10) do
      sleep 0.01 until Dir.children(marker_dir).length == 2
    end
  end
end
