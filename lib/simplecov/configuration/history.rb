# frozen_string_literal: true

module SimpleCov
  # Configuration for the run history (see SimpleCov::History):
  # `history_limit` bounds coverage/.history.json, and `drop_baseline`
  # picks what `maximum_coverage_drop` compares against.
  module Configuration
    DROP_BASELINES = %i[last_run median branch].freeze

    #
    # How many runs coverage/.history.json keeps (default 100, newest
    # kept). 0 disables recording entirely.
    #
    def history_limit(limit = nil)
      return @history_limit ||= 100 if limit.nil?

      unless limit.instance_of?(Integer) && limit >= 0
        raise ConfigurationError, "history_limit takes a non-negative integer, got #{limit.inspect}"
      end

      @history_limit = limit
    end

    #
    # What `maximum_coverage_drop` measures the drop against:
    #
    #   :last_run  (default) the previous run, whatever it was
    #   :median    the median of the recorded history, so one run that
    #              dipped for an unrelated reason cannot quietly become
    #              the baseline the next run is judged against
    #   :branch    the newest recorded run on the current git branch,
    #              so a feature branch is compared with itself rather
    #              than with whatever ran most recently anywhere
    #
    # The :median and :branch baselines read coverage/.history.json and
    # find nothing to compare against while it is empty (or, for
    # :branch, when the branch has no recorded run), which counts as
    # "no previous run" the way a missing .last_run.json does.
    #
    def drop_baseline(mode = nil)
      return @drop_baseline ||= :last_run if mode.nil?

      unless DROP_BASELINES.include?(mode)
        raise ConfigurationError,
              "drop_baseline takes one of #{DROP_BASELINES}, got #{mode.inspect}"
      end

      @drop_baseline = mode
    end
  end
end
