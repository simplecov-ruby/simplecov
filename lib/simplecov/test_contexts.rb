# frozen_string_literal: true

require_relative "test_contexts/test_table"
require_relative "test_contexts/map"
require_relative "test_contexts/recorder"
require_relative "test_contexts/union"
require_relative "test_contexts/hooks"

# Per-test context recording (`SimpleCov.test_contexts :per_test`):
# which test covered each line. The SimpleCov singleton owns the
# process-wide recorder, reopened here.
module SimpleCov
  # Activation entry point; the classes live in test_contexts/.
  module TestContexts
    class << self
      # Called from `SimpleCov.start_tracking` once measuring has begun.
      # Forked children never record: inherited recordings would be wrong.
      def activate!
        return if SimpleCov.forked_subprocess?

        SimpleCov.install_test_context_recorder!
        Hooks.install!
      end
    end
  end

  class << self
    def test_context_recorder
      defined?(@test_context_recorder) ? @test_context_recorder : nil
    end

    # @api private — keeps a live recorder across a second
    # `SimpleCov.start`; replacing it would discard recordings.
    def install_test_context_recorder!
      return if test_context_recorder

      @test_context_recorder = TestContexts::Recorder.new
    end

    # @api private — see `SimpleCov::ProcessForkHook`.
    def clear_test_context_recorder!
      @test_context_recorder = nil
    end

    # @api private — the recording for `Result#to_hash`, or nil when
    # there is nothing trustworthy to store.
    def test_context_payload
      recorder = test_context_recorder
      return nil unless recorder
      return warn_about_missing_test_hooks unless TestContexts::Hooks.installed_any?

      recorder.to_map
    end

  private

    def warn_about_missing_test_hooks
      return nil unless print_errors

      warn "[SimpleCov]: test_contexts :per_test is enabled but neither the RSpec nor the Minitest " \
           "hook was installed, so no per-test contexts were recorded. Call SimpleCov.start from your " \
           "test helper, after the test framework is loaded."
      nil
    end
  end
end
