# frozen_string_literal: true

require_relative "configuration_error"

module SimpleCov
  # Emits legacy-API deprecation warnings, deduplicated by the source location
  # that triggered them. A deprecated method called in a loop, or a config
  # block re-evaluated once per parallel worker, otherwise repeats the same
  # notice until stderr is unreadable. Keying on the caller location collapses
  # those repeats while still warning separately about each distinct call site
  # the user needs to fix (#1204).
  module Deprecation
    extend self

    MODES = %i[warn raise].freeze

    # The mode lives here rather than on the configuration singleton so that
    # `warn` depends on nothing but itself. `SimpleCov.deprecations` is the
    # front door that writes it, and the CLI, which loads none of the
    # configuration surface, can still warn.
    def mode
      @mode ||= :warn
    end

    def mode=(mode)
      raise ConfigurationError, "deprecations takes :warn or :raise, got #{mode.inspect}" unless MODES.include?(mode)

      @mode = mode
    end

    # `message` is the notice without the `[DEPRECATION]` tag or location
    # prefix, both of which are added here. `deprecations :raise` turns every
    # deprecated API into an error before the dedup: an error is not a notice to
    # collapse, and a CI guard must fail on the second offender as surely as on
    # the first. A missing backtrace falls back to keying on the message, so it
    # never silently swallows every notice.
    def warn(message, location: caller_location)
      raise ConfigurationError, message if mode.equal?(:raise)

      return unless emitted.add?(location || message)

      Kernel.warn "#{"#{location}: " if location}[DEPRECATION] #{message}"
    end

    # Every shipped call site is a one-level alias such as `track_files`, so the
    # frame three up from here is the user's own code. `Array(...)` coerces a
    # missing backtrace to `[]` so `.first` yields nil rather than raising.
    def caller_location
      Array(Kernel.caller(3..3)).first
    end

    # Parallel workers are separate processes with their own set, so each warns
    # at most once.
    def emitted
      @emitted ||= Set.new
    end

    def reset!
      @emitted = Set.new
      @mode = :warn
    end
  end
end
