# frozen_string_literal: true

# `~/.simplecov` was historically resolved via a three-step fallback chain
# (HOME, then `Etc.getpwuid.dir`, then `~$USER`) for hostile container
# environments circa 2017. Modern CRuby/JRuby/TruffleRuby all set HOME
# reliably, so trust it and skip silently when it isn't there.
if ENV.fetch("HOME", nil)
  # simplecov:disable — only fires when ~/.simplecov exists, which is
  # developer-machine-dependent (we can't rely on it for the dogfood).
  global_config_path = File.join(File.expand_path("~"), ".simplecov")
  load global_config_path if File.exist?(global_config_path)
  # simplecov:enable
end
