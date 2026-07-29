# frozen_string_literal: true

module CollateBenchmark
  # Polls the process's resident set size on a background thread so a run can
  # report its peak. Memory matters here: the merge fold rebuilds every hash
  # and array it touches, so a change that trades allocations for speed (or the
  # reverse) should be visible.
  class RssSampler
    INTERVAL = 0.25

    def initialize
      @peak = 0
      @running = true
      @thread = Thread.new { sample_until_stopped }
    end

    def peak
      [@peak, RssSampler.current].max
    end

    def stop
      @running = false
      @thread.join
      peak
    end

    # Resident set size in bytes. `ps` behaves the same on macOS and Linux, and
    # at four samples a second the shell out is cheap next to a multi-minute
    # collate.
    def self.current
      `ps -o rss= -p #{Process.pid}`.to_i * 1024
    rescue StandardError
      0
    end

  private

    def sample_until_stopped
      while @running
        @peak = [@peak, RssSampler.current].max
        sleep INTERVAL
      end
    end
  end
end
