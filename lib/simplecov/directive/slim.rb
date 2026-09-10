# frozen_string_literal: true

require_relative "indented_template"

module SimpleCov
  class Directive
    # The Ruby a Slim template holds. Control and output lines (`-`, `=`, `==`,
    # and their whitespace variants) and the output a bare tag carries keep
    # their Ruby with the markers blanked, a `/` comment becomes a Ruby
    # comment, a `ruby:` block's lines are Ruby as written, and everything else
    # is blanked. A tag with attributes is blanked whole, since `=` inside them
    # is not the output marker.
    module Slim
      include IndentedTemplate
      extend self

      CODE = /\A(?:-|={1,2}[<>']*)(?=\s)/
      TAG_CODE = /\A[\w.#-]+\s*={1,2}[<>']*(?=\s)/

      def convert(indent, rest)
        if rest.start_with?("/")
          ["#{indent}##{rest[1..]}", COMMENT]
        elsif rest.match?(/\Aruby:[ \t]*\n\z/)
          [Template.blank(indent + rest), RUBY]
        elsif rest.match?(/\A\w+:[ \t]*\n\z/)
          [Template.blank(indent + rest), TEXT]
        elsif (marker = rest[CODE] || rest[TAG_CODE])
          [indent + Template.blank(marker) + rest[marker.length..]]
        else
          [Template.blank(indent + rest)]
        end
      end
    end
  end
end
