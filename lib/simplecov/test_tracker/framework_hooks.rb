# frozen_string_literal: true

module SimpleCov
  # The test-framework side of per-test tracking: how the wrapper gets
  # installed into RSpec and Minitest, and how each framework's tests are
  # identified. The recording itself lives in test_tracker.rb.
  class TestTracker
    class << self
      def install_framework_hooks
        install_rspec_hook
        install_minitest_hook_when_loaded
      end

      # Wraps every RSpec example in a `track_test` call. Called from
      # `SimpleCov.start_tracking`, where RSpec is already loaded when the suite
      # is an RSpec suite. Installs once per process no matter how often
      # tracking is restarted.
      def install_rspec_hook(rspec = rspec_module)
        return unless rspec
        return if @rspec_hook_installed

        @rspec_hook_installed = true
        rspec.configure do |config|
          # The block runs instance-eval'd in the example group, so everything it
          # touches must be fully qualified.
          config.around do |example|
            SimpleCov.track_test(TestTracker.rspec_example_id(example)) { example.run }
          end
        end
      end

      # The RSpec this process has, if it has one. A Minitest-only suite has
      # none, and no example can make this process into one: hiding the RSpec
      # constant takes down the very runner asking the question.
      # simplecov:disable branch — the RSpec-less arm is unreachable from an RSpec-driven suite
      # mutant:disable
      def rspec_module
        ::RSpec if defined?(::RSpec.configure)
      end
      # simplecov:enable branch

      # @api private -- test seam, so specs can exercise installation repeatedly
      # without touching the process-wide guard for real.
      def reset_rspec_hook!
        @rspec_hook_installed = false
      end

      # Called by the minitest plugin under minitest 5, and by the constant
      # watch below under minitest 6, whose autorun no longer discovers
      # plugins. Prepending a module already in the chain is a no-op, which is
      # the whole of the idempotence.
      def install_minitest_hook(test_case = (Minitest::Test if defined?(Minitest::Test)))
        return if test_case.nil?

        test_case.prepend(MinitestRun)
      end

      # Installs the Minitest wrapper now when Minitest is already loaded, and
      # otherwise the moment `Minitest::Test` is defined. The deferred half is
      # what covers minitest 6 under the canonical helper ordering (SimpleCov
      # first, so coverage sees the app load; minitest after), where no plugin
      # ever fires. `root` is Object outside of tests.
      def install_minitest_hook_when_loaded(root = Object)
        minitest = loaded_const(root, :Minitest)
        test_case = minitest && loaded_const(minitest, :Test)
        return install_minitest_hook(test_case) if test_case
        return watch_for_minitest_test(minitest) if minitest

        ConstantWatch.new(:Minitest) do
          # `loaded_const` rather than the block capturing a module: the module
          # does not exist yet when the watch is armed.
          watch_for_minitest_test(loaded_const(root, :Minitest))
        end.attach(root)
      end

      # Relative the way RSpec prints it (`./spec/a_spec.rb:12` becomes
      # `spec/a_spec.rb:12`).
      def rspec_example_id(example)
        example.metadata.fetch(:location).delete_prefix("./")
      end

      # An autoload declaration fires `const_added` without the module existing
      # yet; that arrangement is left to the plugin, so nil means nothing to
      # watch.
      def watch_for_minitest_test(minitest)
        return unless minitest

        ConstantWatch.new(:Test) { install_minitest_hook(loaded_const(minitest, :Test)) }.attach(minitest)
      end

      # The constant when it is genuinely loaded, nil when absent or merely
      # declared for autoload: const_get would force such a load, and installing
      # a coverage hook must never be what requires a test framework.
      def loaded_const(mod, name)
        return nil unless mod.const_defined?(name, false)
        return nil if mod.autoload?(name, false)

        mod.const_get(name)
      end

      # A Minitest test's identity: the `path:line` where the test method is
      # defined, relative to `SimpleCov.root`. Falls back to
      # `ClassName#method_name` when the method has no source location.
      def minitest_test_id(test)
        path, line = definition_site(test)
        return "#{test.class}##{test.name}" unless path

        "#{path.delete_prefix(File.join(SimpleCov.root, ""))}:#{line}"
      end

      # A method defined in C or through an eval without a filename has no site,
      # and a runner exotic enough to name a method it never defined deserves
      # an id over an exception out of the middle of its run.
      def definition_site(test)
        test.method(test.name).source_location
      rescue NameError
        nil
      end
    end

    # Prepended to `Minitest::Test` by `install_minitest_hook`, wrapping each
    # test method run, setup and teardown included: a line only a setup block
    # reaches is still this test's line.
    module MinitestRun
      def run
        SimpleCov.track_test(TestTracker.minitest_test_id(self)) { super }
      end
    end
  end
end
