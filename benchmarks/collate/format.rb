# frozen_string_literal: true

module CollateBenchmark
  module Format
    extend self

    def duration(seconds)
      return format("%.2fs", seconds) if seconds < 60

      format("%<minutes>dm%<seconds>04.1fs", minutes: seconds / 60, seconds: seconds % 60)
    end

    def delta(now, was)
      return "-" if was.zero?

      format("%+.1f%%", ((now - was) / was) * 100)
    end

    def bytes(count)
      return "n/a" if count.zero?

      format("%.2f GB", count / (1024.0**3))
    end
  end
end
