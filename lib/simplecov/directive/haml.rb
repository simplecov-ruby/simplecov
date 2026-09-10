# frozen_string_literal: true

require_relative "indented_template"

module SimpleCov
  class Directive
    # The Ruby a Haml template holds. Script lines (`-`, `=`, and their `!`,
    # `&`, and `~` variants) and the script a tag outputs keep their Ruby with
    # the markers blanked, a `-#` comment becomes a Ruby comment, a `:ruby`
    # filter's lines are Ruby as written, and everything else is blanked.
    module Haml
      include IndentedTemplate
      extend self

      SCRIPT = /\A[!&]?[-=~]/
      TAG_SCRIPT = /\A[%.#][\w:.#-]*(?:\{[^{}]*\}|\([^()]*\)|\[[^\[\]]*\])*[<>]*[!&]?[=~]/

      def convert(indent, rest)
        if rest.start_with?("-#")
          ["#{indent} ##{rest[2..]}", COMMENT]
        elsif rest.match?(/\A:ruby[ \t]*\n\z/)
          [Template.blank(indent + rest), RUBY]
        elsif rest.start_with?(":")
          [Template.blank(indent + rest), TEXT]
        elsif (marker = rest[SCRIPT] || rest[TAG_SCRIPT])
          [indent + Template.blank(marker) + rest[marker.length..]]
        else
          [Template.blank(indent + rest)]
        end
      end
    end
  end
end
