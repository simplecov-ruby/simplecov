# frozen_string_literal: true

module SimpleCov
  # Drop coverage entries whose paths live outside `SimpleCov.root` so the
  # report only reflects the project's own source. Vendored gems, stdlib
  # files, and anything else that happens to have been touched during the
  # run never make it into the formatted result.
  module UselessResultsRemover
    def self.call(coverage_result)
      coverage_result.select { |path, _coverage| path.match?(root_regx) }
    end

    # The `/i` flag covers case-insensitive matches on Windows / macOS-HFS+
    # where the on-disk path's case can differ from `SimpleCov.root`'s.
    def self.root_regx
      @root_regx ||= /\A#{Regexp.escape(SimpleCov.root.chomp(File::SEPARATOR) + File::SEPARATOR)}/i
    end
  end
end
