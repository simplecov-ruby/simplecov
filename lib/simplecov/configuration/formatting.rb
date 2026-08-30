# frozen_string_literal: true

require_relative "../formatter/multi_formatter"

module SimpleCov
  # Formatter selection (`formats` / `formatter` / `formatters`),
  # reporting toggles (`print_errors`), and the deprecated `# :nocov:`
  # token hook.
  module Configuration
    attr_writer :formatter, :print_error_status

    # The bundled formats `formats` resolves by name, as constant names
    # under SimpleCov::Formatter.
    BUILT_IN_FORMATS = {
      html: :HTMLFormatter, json: :JSONFormatter, simple: :SimpleFormatter, baseline: :BaselineFormatter
    }.freeze
    private_constant :BUILT_IN_FORMATS

    # The bundled formats that live outside the always-loaded core,
    # and where each is required from. Looked up rather than compared
    # for, because every spelling of a Symbol comparison is the same
    # comparison.
    LAZY_FORMAT_REQUIRES = {html: "../../simplecov-html"}.freeze
    private_constant :LAZY_FORMAT_REQUIRES

    #
    # The symbol front door to formatter selection: name the bundled
    # formatters instead of spelling their constants.
    #
    #   SimpleCov.start do
    #     formats :html, :json
    #   end
    #
    # `:html`, `:json`, `:simple`, and `:baseline` map to the bundled
    # formatter classes; anything else (a formatter class, or a
    # ready-built instance for constructor options) passes through
    # beside them, so `formats :html, MyFormatter` mixes freely. With no
    # arguments it reads back the configured formatter list, like
    # `formatters` does.
    #
    def formats(*names)
      return formatters if names.empty?

      self.formatters = names.map { |name| resolve_format(name) }
      formatters
    end

    #
    # Gets or sets the configured formatter. Accepts a formatter class
    # (instantiated fresh for every report) or a ready-built instance,
    # which is how constructor options are passed — e.g.
    # `formatter SimpleCov::Formatter::HTMLFormatter.new(silent: true)`
    # to suppress the "Coverage report generated" status line (see
    # #1240). Pass `false` (or `nil`) to opt out of formatting
    # entirely — worker processes in big parallel CI setups (see #964)
    # only need their `.resultset.json` on disk so a final
    # `SimpleCov.collate` job can produce the report; running them
    # without a formatter saves the per-job HTML/multi-formatter
    # overhead.
    #
    def formatter(formatter = :__no_arg__)
      case formatter
      when :__no_arg__
        @formatter
      else
        @formatter = formatter || nil # normalize `false` to `nil`
      end
    end

    # Sets the configured formatters. Pass `[]` to opt out of
    # formatting entirely; see `formatter` for the rationale.
    def formatters(formatters = :__no_arg__)
      case formatters
      when :__no_arg__
        configured = formatter
        configured ? [configured] : []
      else
        # An assignment answers with what it was given, which is what a
        # caller chaining from this reads.
        self.formatters = formatters
      end
    end

    # Sets the configured formatters. Equivalent to `formatters [...]`.
    # Accepts a single formatter as well as an Array, matching the pre-1.0 behavior
    # where `MultiFormatter.new` normalized its input. Elements may be
    # formatter classes or ready-built instances; see `formatter`.
    # `nil`, `false`, and `[]` all opt out of formatting entirely —
    # `false` normalized like `formatter false` does, since `Array(false)`
    # would otherwise smuggle it in as a "formatter" that can only fail.
    def formatters=(formatters)
      @formatter = combined_formatter(Array(formatters || nil))
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
      return instance_variable_defined?(:@color) ? @color : :auto if value.eql?(:__no_arg__)

      self.color = _ = value
    end

    def color=(value)
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
      return instance_variable_defined?(:@print_error_status) ? @print_error_status : true if value.eql?(:__no_arg__)

      self.print_errors = _ = value
    end

    # The write half of `print_errors`, stored where the deprecated
    # `print_error_status` reads.
    def print_errors=(value)
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
    # The HTML report's embedded data always includes source — the
    # client-side renderer needs it. Only `coverage.json` honors
    # this setting.
    #
    #     SimpleCov.start do
    #       source_in_json false
    #     end
    #
    def source_in_json(value = :__no_arg__)
      return instance_variable_defined?(:@source_in_json) ? @source_in_json : true if value.eql?(:__no_arg__)

      self.source_in_json = _ = value
    end

    def source_in_json=(value)
      @source_in_json = value
    end

    # DEPRECATED: alias for `print_errors`. Same value, same behavior.
    def print_error_status
      Deprecation.warn("`SimpleCov.print_error_status` is deprecated. " \
                       "Replace with `SimpleCov.print_errors` (same value).")
      instance_variable_defined?(:@print_error_status) ? @print_error_status : true
    end

    #
    # DEPRECATED: configure `# :nocov:` token override. Prefer
    # `# simplecov:disable` / `# simplecov:enable` block comments (see
    # SimpleCov::Directive). The `# :nocov:` toggle and this hook will
    # be removed in a future release.
    #
    def nocov_token(nocov_token = nil)
      Deprecation.warn("`SimpleCov.nocov_token` and `SimpleCov.skip_token` are deprecated. " \
                       "Replace with `# simplecov:disable` / `# simplecov:enable` block comments.")
      current_nocov_token(nocov_token)
    end
    alias skip_token nocov_token

    # Internal accessor used by SimpleCov to recognise `# :nocov:`
    # markers without emitting the public-API deprecation warning. Will
    # be removed alongside the deprecated `nocov_token` setter.
    def current_nocov_token(value = nil)
      return @nocov_token if instance_variable_defined?(:@nocov_token) && value.nil?

      @nocov_token = value || "nocov"
    end

  private

    # A `formats` element: Symbols name bundled formatters, everything
    # else passes through as a formatter of its own. `:html` requires
    # the HTML formatter lazily, since under SIMPLECOV_NO_DEFAULTS
    # nothing else has loaded it.
    # One formatter standing for the list, and nothing at all for an
    # empty one: an empty list is how a project opts out of formatting.
    def combined_formatter(formatters)
      return if formatters.empty?

      Formatter::MultiFormatter.new(formatters)
    end

    def resolve_format(name)
      return name unless name.instance_of?(Symbol)

      constant = BUILT_IN_FORMATS[name]
      unless constant
        raise ConfigurationError,
              "Unknown format #{name.inspect}. Built-in formats are :html, :json, :simple, and :baseline; " \
              "pass a formatter class or instance for anything else."
      end

      require_html_formatter(name)
      Formatter.const_get(constant)
    end

    # What makes `formats :html` work in a process that never required
    # the HTML formatter.
    def require_html_formatter(name)
      path = LAZY_FORMAT_REQUIRES[name]
      require_relative(path) if path
    end
  end
end
