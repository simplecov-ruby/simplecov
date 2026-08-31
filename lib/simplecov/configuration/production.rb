# frozen_string_literal: true

module SimpleCov
  module Configuration
    # The path to a production coverage store, the file a `SimpleCov::Production`
    # sink wrote. Relative paths resolve against `SimpleCov.root`. The store is
    # read at report time, and an unreadable or invalid file warns and leaves the
    # section out, because a missing night's data should not fail the suite that
    # measured the tests.
    def production_coverage(path = nil)
      return @production_coverage if path.nil?

      self.production_coverage = path
      @production_coverage
    end

    def production_coverage=(path)
      raise ConfigurationError, "production_coverage takes a path, got #{path.inspect}" unless path.is_a?(String)

      @production_coverage = File.expand_path(path, root)
    end
  end
end
