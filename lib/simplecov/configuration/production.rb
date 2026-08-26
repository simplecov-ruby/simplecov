# frozen_string_literal: true

module SimpleCov
  # Configuration for crossing the report with production coverage (see
  # SimpleCov::Production and docs/Production.md): `production_coverage`
  # names the store a production sink accumulated, and the HTML and JSON
  # formatters then carry its data alongside the test coverage.
  module Configuration
    #
    # Get or set the path to a production coverage store (the file a
    # `SimpleCov::Production` sink wrote, or a remote sink's data
    # downloaded into the same shape). Defaults to nil: no production
    # section in the report. Relative paths resolve against
    # `SimpleCov.root`.
    #
    #   SimpleCov.start do
    #     production_coverage "/var/data/coverage/production.json"
    #   end
    #
    # The store is read at report time; an unreadable or invalid file
    # warns and the report is generated without the section, because a
    # missing night's data should not fail the suite that measured the
    # tests.
    #
    def production_coverage(path = nil)
      return defined?(@production_coverage) ? @production_coverage : nil if path.nil?

      unless path.is_a?(String)
        raise SimpleCov::ConfigurationError, "production_coverage takes a path, got #{path.inspect}"
      end

      @production_coverage = File.expand_path(path, root)
    end
  end
end
