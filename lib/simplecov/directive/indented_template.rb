# frozen_string_literal: true

module SimpleCov
  class Directive
    # The driver the line-oriented template languages share. Each line is
    # converted on its own unless the line above it opened a block, which the
    # language decides by answering a continuation alongside the converted
    # text: `COMMENT` for a comment marker, whose deeper-indented lines
    # continue the comment, `RUBY` for an embedded Ruby block, whose lines are
    # Ruby as written, and `TEXT` for any other embedded block, whose lines are
    # blanked. A blank line neither ends a block nor belongs to it.
    module IndentedTemplate
      COMMENT = ->(line) { line.start_with?("\n") ? line : "##{line[1..]}" }
      RUBY = ->(line) { line }
      TEXT = ->(line) { Template.blank(line) }

      def ruby_lines(lines)
        open = nil #: untyped
        lines.map do |line|
          line = "#{line}\n" unless line.end_with?("\n")
          indent = line[/\A[ \t]*/].length
          rest = line[indent..]
          if open && (rest.eql?("\n") || indent > open.last)
            open.first.call(line)
          else
            converted = convert(line[0, indent], rest)
            continuation = converted.at(1)
            open = continuation && [continuation, indent]
            converted.fetch(0)
          end
        end
      rescue ArgumentError, EncodingError
        lines
      end
    end
  end
end
