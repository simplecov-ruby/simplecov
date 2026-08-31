# frozen_string_literal: true

module CollateBenchmark
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
