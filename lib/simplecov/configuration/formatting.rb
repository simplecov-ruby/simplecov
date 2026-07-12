# frozen_string_literal: true

require_relative "../formatter/multi_formatter"

module SimpleCov
  # Formatter selection (`formatter` / `formatters`), reporting toggles
  # (`print_errors`), and the deprecated `# :nocov:` token hook.
  module Configuration
    attr_writer :formatter, :print_error_status

    #
    # Gets or sets the configured formatter. Pass `false` (or `nil`) to
    # opt out of formatting entirely — worker processes in big parallel
    # CI setups (see #964) only need their `.resultset.json` on disk so
    # a final `SimpleCov.collate` job can produce the report; running
    # them without a formatter saves the per-job HTML/multi-formatter
    # overhead.
    #
    def formatter(formatter = :__no_arg__)
      return @formatter if formatter == :__no_arg__

      @formatter = formatter || nil # normalize `false` to `nil`
    end

    # Sets the configured formatters. Pass `[]` to opt out of
    # formatting entirely; see `formatter` for the rationale.
    def formatters(formatters = :__no_arg__)
      return Array(formatter) if formatters == :__no_arg__

      self.formatters = formatters
      formatters
    end

    # Sets the configured formatters. Equivalent to `formatters [...]`.
    # Accepts a single formatter as well as an Array, matching the pre-1.0 behavior
    # where `MultiFormatter.new` normalized its input.
    def formatters=(formatters)
      formatters = Array(formatters)
      @formatter = formatters.empty? ? nil : SimpleCov::Formatter::MultiFormatter.new(formatters)
    end

    #
    # Get or set whether SimpleCov colorizes its stderr diagnostics. Accepts
    # `true` (always on), `false` (always off), or `:auto` (default: defer
    # to `SimpleCov::Color`, which checks `$stderr.tty?` with `NO_COLOR`
    # and `FORCE_COLOR` overrides). An explicit `true`/`false` wins over
    # both auto-detection and the env vars, which is the right escape
    # hatch when stderr is being piped through a wrapper that still
    # renders ANSI in its own terminal (parallel_tests with
    # `--combine-stderr`, log multiplexers, some CI runners). See #1157.
    #
    def color(value = :__no_arg__)
      return defined?(@color) ? @color : :auto if value == :__no_arg__

      @color = value
    end

    #
    # Get or set whether SimpleCov prints its own diagnostic warnings to
    # stderr. Covers per-check threshold violations, the trailing
    # "SimpleCov failed with exit ..." summary, and the deferred-report /
    # previous-error notices. Defaults to true. Set to false to silence
    # SimpleCov entirely when parsing tooling output (see issue #1155).
    #
    def print_errors(value = :__no_arg__)
      return defined?(@print_error_status) ? @print_error_status : true if value == :__no_arg__

      @print_error_status = value
    end

    #
    # Get or set whether `coverage.json` includes the full source-text
    # array for every file. Defaults to true. Set to false when a
    # downstream tool reads the project's source files directly and
    # only needs the coverage metrics, so `coverage.json` doesn't carry
    # a copy of the source tree (which dominates the payload on larger
    # projects).
    #
    # The HTML viewer's `coverage_data.js` always includes source —
    # the client-side renderer needs it. Only `coverage.json` honors
    # this setting.
    #
    #     SimpleCov.start do
    #       source_in_json false
    #     end
    #
    def source_in_json(value = :__no_arg__)
      return defined?(@source_in_json) ? @source_in_json : true if value == :__no_arg__

      @source_in_json = value
    end

    # DEPRECATED: alias for `print_errors`. Same value, same behavior.
    def print_error_status
      SimpleCov::Deprecation.warn("`SimpleCov.print_error_status` is deprecated. " \
                                  "Replace with `SimpleCov.print_errors` (same value).")
      defined?(@print_error_status) ? @print_error_status : true
    end

    #
    # DEPRECATED: configure `# :nocov:` token override. Prefer
    # `# simplecov:disable` / `# simplecov:enable` block comments (see
    # SimpleCov::Directive). The `# :nocov:` toggle and this hook will
    # be removed in a future release.
    #
    def nocov_token(nocov_token = nil)
      SimpleCov::Deprecation.warn("`SimpleCov.nocov_token` and `SimpleCov.skip_token` are deprecated. " \
                                  "Replace with `# simplecov:disable` / `# simplecov:enable` block comments.")
      current_nocov_token(nocov_token)
    end
    alias skip_token nocov_token

    # Internal accessor used by SimpleCov to recognise `# :nocov:`
    # markers without emitting the public-API deprecation warning. Will
    # be removed alongside the deprecated `nocov_token` setter.
    def current_nocov_token(value = nil)
      return @nocov_token if defined?(@nocov_token) && value.nil?

      @nocov_token = value || "nocov"
    end
  end
end
