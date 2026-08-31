# frozen_string_literal: true

module SimpleCov
  module Configuration
    # The baseline's path, relative to `SimpleCov.root`; an absolute path is
    # honored as given. The file's presence is the opt-in: generate it with
    # `simplecov ratchet`, check it in, and the exit check holds every listed
    # file to its own floor (#1268).
    def baseline_file(path = nil)
      return @baseline_file ||= Baseline::DEFAULT_FILENAME unless path

      self.baseline_file = path
      _ = @baseline_file
    end

    def baseline_file=(path)
      @baseline_file = path
    end

    # Memoized per resolved path so the exit check and the JSON formatter's
    # errors section read the file once, while a `baseline_file` or `root` change
    # between reads is still picked up.
    def baseline
      resolved = File.expand_path(baseline_file, root)
      return @baseline if @baseline_path.eql?(resolved)

      @baseline_path = resolved
      @baseline = Baseline.read(resolved)
    end
  end
end
