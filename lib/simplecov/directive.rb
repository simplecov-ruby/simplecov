# frozen_string_literal: true

require "ripper"

module SimpleCov
  # Parses `# simplecov:disable` / `# simplecov:enable` directive comments, in
  # both the block form (the directive is the entire comment on its own line,
  # opening a region that runs until the matching enable) and the inline form
  # (the directive trails real code, affecting that line alone).
  #
  # Categories are `:line`, `:branch`, and `:method`, combinable with commas.
  # Omitting categories targets all three. Any text after the directive is a
  # free-form reason and is discarded, so an unrecognised category name
  # silently falls into the reason bucket and disables everything: a
  # deliberate over-disable, so the typo is visible in the report rather than
  # silently disabling nothing.
  #
  # Comment extraction goes through `Ripper.lex` so directive markers inside
  # string literals or heredocs are correctly ignored.
  class Directive
    CATEGORIES = %i[line branch method].freeze

    CATEGORY_PATTERN = "(?:#{CATEGORIES.join("|")})".freeze
    CATEGORIES_PATTERN = "(?:#{CATEGORY_PATTERN}(?:\\s*,\\s*#{CATEGORY_PATTERN})*)".freeze
    PATTERN = /
      \#\s*simplecov\s*:\s*
      (?<mode>disable|enable)\b
      (?:\s+(?<categories>#{CATEGORIES_PATTERN})\b)?
      .*?
      \s*\z
    /x

    attr_reader :line_number, :mode, :categories

    # The disabled line ranges per category. An unclosed `disable` block
    # extends to the end of the file.
    def self.disabled_ranges(lines)
      ranges = CATEGORIES.to_h do |category|
        empty = [] # : Array[Range[Integer]]
        [category, empty]
      end
      open_starts = {} # : Hash[Symbol, Integer]

      directives_in(lines).each { |directive| directive.apply(ranges, open_starts) }
      open_starts.each { |category, start| ranges.fetch(category) << (start..lines.size) }

      ranges
    end

    # Every directive in the file, in source order. Comments inside string
    # literals or heredocs are skipped because Ripper.lex doesn't tag them as
    # :on_comment tokens.
    def self.directives_in(lines)
      return [] unless source_might_contain_directive?(lines)

      comments_in(lines).filter_map do |line_number, column, text|
        parse_comment(lines, line_number, column, text)
      end
    end

    # Cheap pre-check, so files that obviously can't contain a directive are
    # never tokenized.
    def self.source_might_contain_directive?(lines)
      lines.any? do |line|
        line.include?("simplecov")
      rescue ArgumentError, EncodingError
        false
      end
    end

    def self.parse_comment(lines, line_number, column, text)
      match = PATTERN.match(text)
      return nil unless match

      new(
        line_number: line_number,
        # The pattern admits exactly two modes, so asking whether this one is
        # `disable` names the other by elimination. Comparing the captured text
        # also keeps the nilable capture out of `to_sym`.
        mode: match[:mode].eql?("disable") ? :disable : :enable,
        categories: parse_categories(match[:categories]),
        inline: inline?(lines, line_number, column + match.begin(0))
      )
    rescue ArgumentError, EncodingError
      # The comment text contains an invalid byte sequence, say.
      nil
    end

    # The bare form targets every category, and answers the frozen constant
    # itself: a directive's categories are only ever iterated.
    def self.parse_categories(text)
      return CATEGORIES if text.nil?

      text.split(/\s*,\s*/).map(&:to_sym)
    end

    # `column` is the byte column of the directive's `#` in the source line,
    # adjusted for any prefix that may precede it within the comment token.
    def self.inline?(lines, line_number, column)
      line = lines.at(line_number - 1).to_s
      # Indentation is all a non-inline directive may have before it, so
      # stripping the prefix from the left decides the question. Doing it from
      # the right instead would raise on a line whose trailing bytes are
      # invalid, which is a property of the code after the directive.
      !line.byteslice(0, column).to_s.lstrip.empty?
    rescue ArgumentError, EncodingError
      false
    end

    def self.comments_in(lines)
      source = lines.map { |line| line.end_with?("\n") ? line : "#{line}\n" }.join
      Ripper.lex(source).filter_map do |(line_number, column), type, text|
        [line_number, column, text] if type.equal?(:on_comment)
      end
    rescue ArgumentError, EncodingError
      []
    end

    private_class_method :directives_in, :source_might_contain_directive?,
      :parse_comment, :parse_categories, :inline?, :comments_in

    def initialize(line_number:, mode:, categories:, inline:)
      @line_number = line_number
      @mode = mode
      @categories = categories
      @inline = inline
    end

    def disabled?
      mode.equal?(:disable)
    end

    def inline?
      @inline
    end

    # Inline directives mark just their line; block disables open a region;
    # block enables close one. Re-opening an already-open block is a no-op.
    def apply(ranges, open_starts)
      categories.each do |category|
        if inline?
          ranges.fetch(category) << (line_number..line_number) if disabled?
        elsif disabled?
          open_starts[category] ||= line_number
        elsif (start = open_starts.delete(category))
          ranges.fetch(category) << (start..line_number)
        end
      end
    end
  end
end
