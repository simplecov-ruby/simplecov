# frozen_string_literal: true

module SimpleCov
  #
  # Select the files that related to working scope directory of SimpleCov
  #
  module UselessResultsRemover
    ROOT_REGX = /\A#{Regexp.escape(SimpleCov.root + File::SEPARATOR)}/io.freeze

    def self.call(coverage_result)
      coverage_result.select do |path, _coverage|
        path =~ ROOT_REGX
      end
    end
  end
end
