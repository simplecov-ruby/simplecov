# frozen_string_literal: true

require "json"

module SimpleCov
  # Shared parser for coverage.json consumers. It enforces the encoding and
  # stable outermost shape while leaving command- or viewer-specific fields to
  # their respective callers.
  module CoverageJSON
    class Error < StandardError; end

    def self.load(path)
      source = File.binread(path).force_encoding(Encoding::UTF_8)
      raise Error, "input is not valid UTF-8" unless source.valid_encoding?

      document = JSON.parse(source)
      return document if document.instance_of?(Hash)

      raise Error, "top-level value must be an object"
    rescue JSON::ParserError => e
      raise Error, e
    end
  end
end
