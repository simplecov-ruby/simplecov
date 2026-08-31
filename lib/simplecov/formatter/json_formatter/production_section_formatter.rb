# frozen_string_literal: true

require_relative "../../production/file_sink"

module SimpleCov
  module Formatter
    class JSONFormatter
      module ProductionSectionFormatter
        extend self

        # The section for the configured store, or nil when none is configured or it
        # is unreadable. An unreadable store warns instead of raising: the report is
        # generated at the end of a test run, and a missing night of production data
        # must not fail the suite that measured the tests.
        def call(path = SimpleCov.production_coverage)
          return nil unless path

          section(Production::FileSink.read(path))
        rescue SystemCallError, Production::Error => e
          warn "[SimpleCov] skipping production coverage (#{e})"
        end

        def section(store)
          section = {} #: Hash[Symbol, untyped]
          started_at = store["started_at"]
          updated_at = store["updated_at"]
          section[:started_at] = started_at if started_at
          section[:updated_at] = updated_at if updated_at
          section[:files] = files(store)
          section
        end

        # `coverage` and `last_seen` are the two keys a parsed store always carries,
        # since `FileSink.parse` substitutes an empty Hash for either one a document
        # is missing.
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
