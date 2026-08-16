# frozen_string_literal: true

# How minitest plugins. See https://github.com/simplecov-ruby/simplecov/pull/756 for why we need this.
# https://github.com/seattlerb/minitest#writing-extensions
#
# Handles the SimpleCov-first / Minitest-second ordering: SimpleCov.start
# runs before `require "minitest/autorun"`, so the SimpleCov.start-time
# detection in `install_at_exit_hook` can't see Minitest yet. By the time
# this plugin fires (inside `Minitest.run`), Minitest is loaded and we
# can flip the same switch. The opposite ordering (Minitest first) is
# handled in `SimpleCov.install_at_exit_hook` — see `#minitest_autorun_pending?`.
module Minitest
  def self.plugin_simplecov_init(_options)
    return unless defined?(SimpleCov)

    # Per-test tracking wraps each test method run. Installed here for the
    # same ordering reason as the at_exit switch below: by plugin time both
    # Minitest and the user's `SimpleCov.start` configuration exist,
    # whichever loaded first. The respond_to? guard covers a process where
    # only simplecov's version file was loaded (see issue #877), which
    # defines the SimpleCov constant without any of its configuration.
    SimpleCov::TestTracker.install_minitest_hook if SimpleCov.respond_to?(:track_tests?) && SimpleCov.track_tests?

    return if SimpleCov.external_at_exit?

    SimpleCov.external_at_exit = true

    Minitest.after_run do
      SimpleCov.at_exit_behavior
    end
  end
end
