# frozen_string_literal: true

# `~/.simplecov` was historically resolved through a three-step fallback chain
# for hostile container environments circa 2017. Modern CRuby and JRuby both set
# HOME reliably, so trust it and skip silently when it isn't there. An ENV check
# rather than `Dir.home`: JRuby raises from `Dir.home` with HOME unset, and
# `File.expand_path("~")` raises for a set-but-empty HOME, which must not break
# `require "simplecov"`.

unless ENV.fetch("HOME", "").empty?
  # simplecov:disable — only fires when ~/.simplecov exists, which is
  # developer-machine-dependent (we can't rely on it for the dogfood).
  global_config_path = File.join(File.expand_path("~"), ".simplecov")
  load global_config_path if File.exist?(global_config_path)
  # simplecov:enable
end
