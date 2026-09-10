# frozen_string_literal: true

require_relative "erb"
require_relative "haml"
require_relative "slim"

module SimpleCov
  class Directive
    # Hands a template's lines to the extractor for its language, so the
    # directive scan sees only the Ruby a template holds, at the template's own
    # line numbers. A file in no template language is Ruby already.
    module Template
      EXTRACTORS = {".erb" => Erb, ".haml" => Haml, ".slim" => Slim}.freeze

      def self.template?(filename)
        EXTRACTORS.key?(File.extname(filename))
      end

      def self.ruby_lines(filename, lines)
        extractor = EXTRACTORS[File.extname(filename)]
        extractor ? extractor.ruby_lines(lines) : lines
      end

      def self.blank(text)
        text.gsub(/[^\n]/, " ")
      end
    end
  end
end
