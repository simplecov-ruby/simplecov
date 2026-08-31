# frozen_string_literal: true

module SimpleCov
  # Drops coverage entries whose paths live outside `SimpleCov.root`, so vendored
  # gems, stdlib files, and anything else touched during the run never make it
  # into the formatted result.
  module UselessResultsRemover
    def self.call(coverage_result)
      coverage_result.select { |path, _coverage| path.match?(root_regex) }
    end

    # The `/i` flag covers case-insensitive matches on Windows and macOS-HFS+,
    # where the on-disk path's case can differ from `SimpleCov.root`'s.
    def self.root_regex
      root = SimpleCov.root
      return @root_regex if root.eql?(@root_regex_root)

      @root_regex_root = root
      @root_regex = /\A#{Regexp.escape(root.chomp(File::SEPARATOR) + File::SEPARATOR)}/i
    end

    def self.root_regx
      Deprecation.warn("`SimpleCov::UselessResultsRemover.root_regx` is deprecated. " \
                       "Replace with `root_regex`.")
      root_regex
    end
  end
end
