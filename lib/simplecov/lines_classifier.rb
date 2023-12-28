# frozen_string_literal: true

module SimpleCov
  # Classifies whether lines are relevant for code coverage analysis.
  # Comments & whitespace lines, and :nocov: token blocks, are considered not relevant.

  class LinesClassifier
    RELEVANT = 0
    NOT_RELEVANT = nil

    WHITESPACE_LINE = /^\s*$/.freeze
    COMMENT_LINE = /^\s*#/.freeze
    WHITESPACE_OR_COMMENT_LINE = Regexp.union(WHITESPACE_LINE, COMMENT_LINE)

    def self.no_cov_block
      /^(\s*)#(\s*)(:#{SimpleCov.nocov_token}:)/o
    end

    def self.no_cov_line
      /#(\s*)(:#{SimpleCov.nocov_token}:)(\s*)$/o
    end

    def self.no_cov_line?(line)
      no_cov_line.match?(line)
    rescue ArgumentError
      # E.g., line contains an invalid byte sequence in UTF-8
      false
    end

    def self.no_cov_block?(line)
      no_cov_block.match?(line)
    rescue ArgumentError
      # E.g., line contains an invalid byte sequence in UTF-8
      false
    end

    def self.whitespace_line?(line)
      WHITESPACE_OR_COMMENT_LINE.match?(line)
    rescue ArgumentError
      # E.g., line contains an invalid byte sequence in UTF-8
      false
    end

    def classify(lines)
      skipping = false

      lines.map do |line|
        if self.class.no_cov_block?(line)
          skipping = !skipping
          NOT_RELEVANT
        elsif skipping || self.class.no_cov_line?(line) || self.class.whitespace_line?(line)
          NOT_RELEVANT
        else
          RELEVANT
        end
      end
    end
  end
end
