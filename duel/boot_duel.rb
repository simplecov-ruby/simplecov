# frozen_string_literal: true

# What `require "simplecov"` costs every test process, before any test
# runs. Prism loads only when branch or method coverage needs it, and this
# guards that it stays that way.
duel_process "boot: require simplecov", ruby: %(require "simplecov")
