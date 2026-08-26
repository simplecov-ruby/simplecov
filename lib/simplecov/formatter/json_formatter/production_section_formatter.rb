# frozen_string_literal: true

require_relative "../../production/file_sink"

module SimpleCov
  module Formatter
    class JSONFormatter
      # Builds the optional `production` section of coverage.json from a
      # configured production coverage store (see `SimpleCov.production_coverage`
      # and docs/Production.md): the window the data spans and, per
      # root-relative path, the lines production ran plus the store's
      # recency stamp. File keys match the `coverage` section's, so
      # consumers (the HTML viewer included) cross the two by key.
      module ProductionSectionFormatter
      module_function

        # The section for the configured store, or nil — not configured,
        # or unreadable. An unreadable store warns instead of raising:
        # the report is generated at the end of a test run, and a
        # missing night of production data must not fail the suite that
        # measured the tests.
        def call(path = SimpleCov.production_coverage)
          return nil unless path

          section(SimpleCov::Production::FileSink.read(path))
        rescue SystemCallError, SimpleCov::Production::Error => e
          warn "[SimpleCov] skipping production coverage (#{e.message})"
          nil
        end

        def section(store)
          section = {} #: Hash[Symbol, untyped]
          section[:started_at] = store["started_at"] if store["started_at"]
          section[:updated_at] = store["updated_at"] if store["updated_at"]
          section[:files] = files(store)
          section
        end

        def files(store)
          last_seen = store["last_seen"]
          store["coverage"].sort.to_h do |file, lines|
            entry = {lines: lines} #: Hash[Symbol, untyped]
            stamp = last_seen[file]
            entry[:last_seen] = stamp if stamp
            [file, entry]
          end
        end
      end
    end
  end
end
