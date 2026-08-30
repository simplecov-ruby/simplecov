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
      return @production_coverage if path.nil?

      self.production_coverage = path
      @production_coverage
    end

    # The write half of `production_coverage`: a path, expanded against
    # the root, and nothing else.
    def production_coverage=(path)
      raise ConfigurationError, "production_coverage takes a path, got #{path.inspect}" unless path.is_a?(String)

      @production_coverage = File.expand_path(path, root)
    end
  end
end
