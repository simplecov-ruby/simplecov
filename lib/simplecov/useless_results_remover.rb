# frozen_string_literal: true

module SimpleCov
  #
  # Select the files that related to working scope directory of SimpleCov
  #
  module UselessResultsRemover
    def self.call(coverage_result)
      coverage_result.select do |path, _coverage|
        path =~ root_regx
      end
    end

    def self.root_regx
      @root_regx ||= begin
        prefix = SimpleCov.root
        prefix += File::SEPARATOR unless prefix.end_with?(File::SEPARATOR)
        /\A#{Regexp.escape(prefix)}/i
      end
    end
  end
end
