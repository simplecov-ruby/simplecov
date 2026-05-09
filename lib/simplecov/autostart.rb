# frozen_string_literal: true

# Loaded via `RUBYOPT="-rsimplecov/autostart"` from `simplecov run`. The
# `require "simplecov"` here also auto-loads `~/.simplecov` and the
# project's `.simplecov` (per simplecov/defaults.rb), which may already
# call `SimpleCov.start`. `SimpleCov.start` is idempotent — it won't
# restart Coverage if it's already running, and `install_at_exit_hook`
# guards against double-installing — so calling it unconditionally is
# the safe way to ensure the report is formatted at exit.
require "simplecov"
SimpleCov.start
