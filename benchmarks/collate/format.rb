# frozen_string_literal: true

module CollateBenchmark
  # Number formatting for the report tables. Kept apart from `Report` so that
  # class stays about the shape of the output rather than its units.
  module Format
    extend self

    # A collate at full scale runs into minutes, so seconds alone stop being
    # readable past the first phase.
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
