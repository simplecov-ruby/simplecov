# frozen_string_literal: true

module SimpleCov
  # ANSI colorization for stderr diagnostics. Thresholds mirror the
  # HTML formatter (>= 90 green, >= 75 yellow, otherwise red) so a
  # team's mental model of "what's the cutoff" is the same whether
  # they're reading the terminal output or the HTML report.
  #
  # Color is on only when stderr is a TTY, with the usual env-var
  # overrides:
  #
  # - `NO_COLOR` (any non-empty value) → force off (see no-color.org)
  # - `FORCE_COLOR` (any non-empty value) → force on
  # - `NO_COLOR` wins if both are set
  module Color
    GREEN_THRESHOLD  = 90
    YELLOW_THRESHOLD = 75

    ANSI = {
      red: "\e[31m",
      yellow: "\e[33m",
      green: "\e[32m",
      reset: "\e[0m"
    }.freeze

  module_function

    # `stream` is the IO that the colorized text is destined for. The
    # formatter writes to stderr, so that's the default; CLI subcommands
    # that print to stdout should pass `$stdout` so a redirected pipe
    # doesn't get ANSI sequences. `NO_COLOR` / `FORCE_COLOR` env vars
    # short-circuit either direction.
    def enabled?(stream = $stderr)
      return false if env_set?("NO_COLOR")
      return true  if env_set?("FORCE_COLOR")

      stream.tty?
    end

    def for_percent(percent)
      return :green  if percent >= GREEN_THRESHOLD
      return :yellow if percent >= YELLOW_THRESHOLD

      :red
    end

    # Wrap `text` in the ANSI sequence for `color` (a key of ANSI).
    # Returns the bare text if color is disabled. The `enabled:`
    # keyword lets callers (e.g., CLI subcommands honoring `--no-color`)
    # override the auto-detection without touching env vars.
    def colorize(text, color, enabled: enabled?)
      return text unless enabled

      "#{ANSI.fetch(color)}#{text}#{ANSI.fetch(:reset)}"
    end

    # Render `percent` as a fixed "NN.NN%" string colored by which
    # threshold band it falls into. Callers that want a different
    # rendering of the number can pass the pre-rendered `text`.
    def colorize_percent(percent, text = nil, enabled: enabled?)
      colorize(text || format("%.2f%%", percent), for_percent(percent), enabled: enabled)
    end

    def env_set?(name)
      value = ENV.fetch(name, nil)
      value && !value.empty?
    end
  end
end
