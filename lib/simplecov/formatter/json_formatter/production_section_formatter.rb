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
        extend self

        # The section for the configured store, or nil — not configured,
        # or unreadable. An unreadable store warns instead of raising:
        # the report is generated at the end of a test run, and a
        # missing night of production data must not fail the suite that
        # measured the tests.
        def call(path = SimpleCov.production_coverage)
          return nil unless path

          section(Production::FileSink.read(path))
        rescue SystemCallError, Production::Error => e
          # Interpolating the exception renders its message, and `warn`
          # answers nil, which is what an unreadable store reports.
          warn "[SimpleCov] skipping production coverage (#{e})"
        end

        # Each end of the window is read once and then tested, rather
        # than read again inside the guard: a second read of a value the
        # guard has already vouched for is a step nothing can observe.
        def section(store)
          section = {} #: Hash[Symbol, untyped]
          started_at = store["started_at"]
          updated_at = store["updated_at"]
          section[:started_at] = started_at if started_at
          section[:updated_at] = updated_at if updated_at
          section[:files] = files(store)
          section
        end

        # `coverage` and `last_seen` are the two keys a parsed store
        # always carries (FileSink.parse substitutes an empty Hash for
        # either one a document is missing), so the reads state that.
        # The window stamps get no such guarantee and stay `[]` reads.
        def files(store)
          last_seen = store.fetch("last_seen")
          store.fetch("coverage").sort.to_h do |file, lines|
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
