# frozen_string_literal: true

# Use system uptime (monotonic time) to calculate accurate and reliable elapsed time.
#
# Question:
#   Why not just do:
#     elapsed_time = Time.now - other_time
# Answer:
#   It is not accurate or reliable.
#     https://blog.dnsimple.com/2018/03/elapsed-time-with-ruby-the-right-way/
module SimpleCov
  class Timer
    # Monotonic clock: Process::CLOCK_MONOTONIC
    # Wall clock: Process::CLOCK_REALTIME
    attr_accessor :start_time, :clock

    class << self
      def monotonic
        read(Process::CLOCK_MONOTONIC)
      end

      def wall
        read(Process::CLOCK_REALTIME)
      end

      # SimpleCov::Timer.read(Process::CLOCK_MONOTONIC) # => uptime in seconds (guaranteed directionally accurate)
      # SimpleCov::Timer.read(Process::CLOCK_REALTIME) # => seconds since EPOCH (may not be directionally accurate)
      def read(clock = Process::CLOCK_MONOTONIC)
        Process.clock_gettime(clock)
      end
    end

    # Capture Time when instantiated
    def initialize(start_time, clock = Process::CLOCK_MONOTONIC)
      @start_time = start_time || self.class.read(clock)
      @clock = clock
    end

    # Get Elapsed Time in Seconds
    def elapsed_seconds
      (self.class.read(clock) - @start_time).truncate
    end
  end
end
