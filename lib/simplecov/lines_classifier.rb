# frozen_string_literal: true

require "set"
require_relative "directive"

module SimpleCov
  # Classifies whether lines are relevant for code coverage analysis.
  # Comments & whitespace lines, and :nocov: token blocks, are considered not relevant.

  class LinesClassifier
    RELEVANT = 0
    NOT_RELEVANT = nil

    WHITESPACE_LINE = /^\s*$/.freeze
    COMMENT_LINE = /^\s*#/.freeze
    WHITESPACE_OR_COMMENT_LINE = Regexp.union(WHITESPACE_LINE, COMMENT_LINE)

    def self.no_cov_line
      /^(\s*)#(\s*)(:#{SimpleCov.current_nocov_token}:)/o
    end

    def self.no_cov_line?(line)
      no_cov_line.match?(line)
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
      lines = lines.to_a
      directive_disabled = directive_disabled_line_set(lines)
      skipping = false

      lines.map.with_index(1) do |line, line_number|
        skipping = !skipping if self.class.no_cov_line?(line)
        not_relevant_line?(line, line_number, skipping, directive_disabled) ? NOT_RELEVANT : RELEVANT
      end
    end

  private

    def not_relevant_line?(line, line_number, skipping, directive_disabled)
      skipping ||
        self.class.no_cov_line?(line) ||
        directive_disabled.include?(line_number) ||
        self.class.whitespace_line?(line)
    end

    def directive_disabled_line_set(lines)
      Directive.disabled_ranges(lines).fetch(:line).each_with_object(Set.new) do |range, set|
        range.each { |line_number| set.add(line_number) }
      end
    end
  end
end
