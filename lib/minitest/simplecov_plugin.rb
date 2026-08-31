# frozen_string_literal: true

module Minitest
  # Handles the SimpleCov-first / Minitest-second ordering: `SimpleCov.start`
  # runs before `require "minitest/autorun"`, so its start-time detection can't
  # see Minitest yet, but by the time this plugin fires Minitest is loaded and
  # the same switch can be flipped. The opposite ordering is handled in
  # `SimpleCov.install_at_exit_hook` (#756).
  #
  # The respond_to? guards cover a process where only simplecov's version file
  # was loaded (#877), which defines the SimpleCov constant without any of its
  # configuration.
  def self.plugin_simplecov_init(_options)
    return unless defined?(SimpleCov)

    SimpleCov::TestTracker.install_minitest_hook if SimpleCov.respond_to?(:track_tests?) && SimpleCov.track_tests?

    return if SimpleCov.external_at_exit?

    SimpleCov.external_at_exit = true

    Minitest.after_run do
      SimpleCov.at_exit_behavior
    end
  end
end
