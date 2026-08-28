# frozen_string_literal: true

module SimpleCov
  # Emits legacy-API deprecation warnings, deduplicated by the source
  # location that triggered them. A deprecated method called in a loop —
  # or a config block re-evaluated once per parallel worker / spec file —
  # otherwise repeats the same notice until stderr is unreadable. Keying
  # on the caller location collapses those repeats to a single line while
  # still warning separately about each distinct call site the user needs
  # to fix. See issue #1204.
  module Deprecation
    extend self

    # Warn about a deprecated API. `message` is the notice without the
    # `[DEPRECATION]` tag or location prefix (both are added here).
    #
    # `location` defaults to the caller of the deprecated method that
    # called us — every shipped call site is a one-level alias such as
    # `track_files`, so the frame two up is the user code. Pass `location:`
    # explicitly when the relevant site isn't that frame (e.g. a source
    # file and line discovered while parsing).
    # `Array(...)` coerces a missing backtrace (nil) to `[]` so `.first`
    # yields nil rather than raising — and, unlike `&.`, adds no branch for
    # the unreachable no-caller case to the project's 100% coverage target.
    def warn(message, location: caller_location)
      # `deprecations :raise` turns every deprecated API into an error,
      # before the dedup: an error is not a notice to collapse, and a
      # CI guard must fail on the second offender file as surely as on
      # the first.
      raise ConfigurationError, message if SimpleCov.deprecations.equal?(:raise)

      # Key on location when we have one (collapses a deprecated call in a
      # loop to a single warning); fall back to the message so a missing
      # backtrace never silently swallows every notice.
      return unless emitted.add?(location || message)

      Kernel.warn "#{"#{location}: " if location}[DEPRECATION] #{message}"
    end

    # The caller of the deprecated method that called us. Every shipped
    # call site is a one-level alias such as `track_files`, so the frame
    # three up from here is the user's own code.
    #
    # `Array(...)` coerces a missing backtrace (nil) to `[]` so `.first`
    # yields nil rather than raising.
    def caller_location
      Array(Kernel.caller(3..3)).first
    end

    # Already-emitted dedup keys for this process. Parallel workers are
    # separate processes with their own set, so each warns at most once.
    def emitted
      @emitted ||= Set.new
    end

    # @api private — reset emitted state between tests.
    def reset!
      @emitted = Set.new
    end
  end
end
