# frozen_string_literal: true

module SimpleCov
  # Configuration for the per-file coverage baseline (see
  # `SimpleCov::Baseline` and #1268). The file's presence is the opt-in:
  # generate it with `simplecov ratchet`, check it in, and the exit
  # check holds every listed file to its own floor. `baseline_file`
  # only needs calling when the file lives somewhere other than
  # `.simplecov_baseline.yml` under the project root.
  module Configuration
    #
    # The baseline's path, relative to `SimpleCov.root` (an absolute
    # path is honored as given). Call with an argument to change it:
    #
    #   SimpleCov.start do
    #     baseline_file "config/coverage_floors.yml"
    #   end
    #
    def baseline_file(path = nil)
      return @baseline_file ||= SimpleCov::Baseline::DEFAULT_FILENAME unless path

      @baseline_file = path
    end

    # The parsed baseline, or nil when the file does not exist. Memoized
    # per resolved path so the exit check and the JSON formatter's
    # errors section read the file once, while a `baseline_file` (or
    # `root`) change between reads is still picked up.
    def baseline
      resolved = File.expand_path(baseline_file, root)
      return @baseline if defined?(@baseline) && @baseline_path == resolved

      @baseline_path = resolved
      @baseline = SimpleCov::Baseline.read(resolved)
    end
  end
end
