# frozen_string_literal: true

require_relative "directive"

module SimpleCov
  # Classifies whether lines are relevant for code coverage analysis.
  # Comments & whitespace lines, and :nocov: token blocks, are considered not relevant.
  class LinesClassifier
    RELEVANT = 0
    NOT_RELEVANT = nil

    WHITESPACE_LINE = /^\s*$/
    COMMENT_LINE = /^\s*#/
    WHITESPACE_OR_COMMENT_LINE = Regexp.union(WHITESPACE_LINE, COMMENT_LINE)

    # The leading `^(\s*)#` anchor is load-bearing beyond matching the marker:
    # `classify_line` only reaches this for lines that already passed
    # `whitespace_line?`, which is sound only while every marker is also a
    # comment. Loosening this to match a trailing `x = 1 # :nocov:` would stop
    # the toggle firing. `lines_classifier_spec.rb` pins the implication.
    #
    # The `/o` flag freezes the interpolated nocov token at this
    # process's first classification; a `nocov_token` configured after
    # coverage has classified a file would be silently ignored. Sound
    # today because configuration always precedes classification.
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

    # Whether the lines being classified are inside a `:nocov:` pair.
    # A named state rather than a one-slot array, so reading it and
    # turning it over each have the one spelling.
    class SkipState
      def initialize
        @skipping = false
      end

      def skipping?
        @skipping
      end

      def toggle
        @skipping = !@skipping
      end
    end

    def classify(lines)
      lines = lines.to_a
      directive_disabled = directive_disabled_line_set(lines)
      # The `:nocov:` skip state lives in a one-slot box owned by this
      # call, not in an ivar, so one classifier instance can serve
      # concurrent `classify` calls without the toggles interleaving.
      skip_state = SkipState.new

      lines.map.with_index(1) do |line, line_number|
        classify_line(line, line_number, directive_disabled, skip_state)
      end
    end

  private

    # A `:nocov:` marker is itself a comment, so the cheap
    # whitespace-or-comment test can gate the token match: a line of real
    # code cannot be a marker, and no longer pays to be checked against
    # one. That matters because this runs per line of every
    # tracked-but-unloaded file, once in every process of a parallel run.
    # mutant:disable — `NOT_RELEVANT` is nil, so naming it and writing
    # the literal are the same value, and so is an `unless` that falls
    # off its end. The name is kept because it says which of the two
    # verdicts a line got, which nil alone does not.
    def classify_line(line, line_number, directive_disabled, skip_state)
      if self.class.whitespace_line?(line)
        skip_state.toggle if self.class.no_cov_line?(line)
        NOT_RELEVANT
      elsif skip_state.skipping? || directive_disabled.include?(line_number)
        NOT_RELEVANT
      else
        RELEVANT
      end
    end

    def directive_disabled_line_set(lines)
      Directive.disabled_ranges(lines).fetch(:line).each_with_object(Set.new) do |range, set|
        range.each { |line_number| set.add(line_number) }
      end
    end
  end
end
