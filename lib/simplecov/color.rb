# frozen_string_literal: true

module SimpleCov
  # ANSI colorization for stderr diagnostics. Thresholds mirror the HTML
  # formatter so a team's mental model of "what's the cutoff" is the same in
  # the terminal and in the report.
  module Color
    GREEN_THRESHOLD  = 90
    YELLOW_THRESHOLD = 75

    ANSI = {
      red: "\e[31m",
      yellow: "\e[33m",
      green: "\e[32m",
      reset: "\e[0m"
    }.freeze

    extend self

    # Precedence, highest first: an explicit `SimpleCov.color` true/false (the
    # default `:auto` falls through), then `NO_COLOR`, then `FORCE_COLOR`, then
    # `stream.tty?`. `NO_COLOR` wins over `FORCE_COLOR` when both are set.
    #
    # `stream` is the IO the colorized text is destined for. CLI subcommands
    # that print to stdout should pass `$stdout` so a redirected pipe doesn't
    # get ANSI sequences.
    #
    # `SimpleCov.color` only exists once the full library is loaded, and the
    # standalone CLI loads this file without it, so a missing config reads as
    # its `:auto` default. A parallel runner can also close a worker's stdio
    # before its at_exit hooks run, and a closed stream is not a tty.
    def enabled?(stream = $stderr)
      config = SimpleCov.color if SimpleCov.respond_to?(:color)
      return config if [true, false].include?(config)
      return false if env_set?("NO_COLOR")
      return true  if env_set?("FORCE_COLOR")

      stream.tty?
    rescue IOError
      false
    end

    def for_percent(percent)
      return :green  if percent >= GREEN_THRESHOLD
      return :yellow if percent >= YELLOW_THRESHOLD

      :red
    end

    def colorize(text, color, enabled: enabled?)
      return text unless enabled

      "#{ANSI.fetch(color)}#{text}#{ANSI.fetch(:reset)}"
    end

    def colorize_percent(percent, text = nil, enabled: enabled?)
      colorize(text || format("%.2f%%", percent), for_percent(percent), enabled: enabled)
    end

    def env_set?(name)
      value = ENV.fetch(name, nil)
      value && !value.empty?
    end
  end
end
