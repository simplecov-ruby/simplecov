# frozen_string_literal: true

module SimpleCov
  class Directive
    # The Ruby an ERB template holds, at the template's own line numbers, so
    # directive comments in a template are found the way they are in a `.rb`
    # file. Lexing the template itself as Ruby is not an option: `%>` opens a
    # percent literal that swallows everything up to the next `>`, so comments
    # after the first tag are never tokenized.
    #
    # Text outside the tags is blanked and the tag delimiters become spaces, so
    # every token keeps its line and column. A comment tag becomes a Ruby
    # comment, which makes `<%# simplecov:disable %>` the template's own form of
    # the directive.
    module Erb
      SEGMENT = /
        (?<escaped><%%)
        | <%(?<kind>\#|==?|-)?(?<body>.*?)(?<close>-?%>)
        | (?<text>[^<]+|<)
      /mx

      def self.ruby_lines(lines)
        source = lines.map { |line| line.end_with?("\n") ? line : "#{line}\n" }.join
        source.gsub(SEGMENT) { convert(Regexp.last_match) }.lines
      rescue ArgumentError, EncodingError
        lines
      end

      def self.convert(match)
        body = match[:body]
        return blank(match[0]) if body.nil?
        return "  #" + body.gsub("\n", "\n#") + blank(match[:close]) if match[:kind].eql?("#")

        blank("<%" + match[:kind].to_s) + body + blank(match[:close]).sub(" ", ";")
      end

      def self.blank(text)
        Template.blank(text)
      end

      private_class_method :convert, :blank
    end
  end
end
