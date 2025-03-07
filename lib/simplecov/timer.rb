# frozen_string_literal: true

# Use system uptime to calculate accurate and reliable elapsed time.
#
# Question:
#   Why not just do:
#     elapsed_time = Time.now - other_time
# Answer:
#   It is not accurate or reliable.
#     https://blog.dnsimple.com/2018/03/elapsed-time-with-ruby-the-right-way/
module SimpleCov
  class Timer
    attr_accessor :start_time

    class << self
      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    # Capture Time when instantiated
    def initialize(start_time)
      @start_time = start_time || self.class.monotonic
    end

    # Get Elapsed Time in Seconds
    def elapsed_seconds
      (self.class.monotonic - @start_time).truncate
    end
  end
end
