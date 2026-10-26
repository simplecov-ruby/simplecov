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
        watch_test_file_loads
      end

      # Reports every file the process loads from here on to the live tracker's
      # `test_file_loading`, which is how a spec file's loading is told apart
      # from the suite's. nil on a Ruby that cannot report a file's compilation
      # (JRuby), where loading stays with no test.
      def watch_test_file_loads
        TracePoint.new(:script_compiled) do |trace|
          # simplecov:disable — Coverage does not count code run inside a TracePoint callback
          path = trace.instruction_sequence.absolute_path
          SimpleCov.test_tracker&.test_file_loading(path) if path
          # simplecov:enable
        end.tap(&:enable)
      rescue ArgumentError
        nil
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
          config.prepend_before(:suite) do
            SimpleCov.test_tracker&.suite_starting
            TestTracker.note_rspec_examples(rspec.world.all_examples)
            # RSpec reports a group starting ahead of all its before(:all)
            # hooks, whatever order they were added in. Registered here
            # because asking for the reporter any earlier sets up the default
            # formatter before the suite has chosen its own.
            config.reporter.register_listener(TestTracker, :example_group_started, :example_started)
          end
        end
      end

      # Called by RSpec's reporter as each group starts, nested ones too, so
      # their before(:all) hooks go to their spec file rather than to the test
      # before them.
      def example_group_started(notification)
        metadata = notification.group.metadata
        SimpleCov.test_tracker&.test_file_starting(rspec_path(metadata.fetch(:rerun_file_path), metadata))
      end

      # Called by RSpec's reporter as each example starts, skipped ones too,
      # which never reach the around hook.
      def example_started(notification)
        example = notification.example
        SimpleCov.test_tracker&.test_started(rspec_example_id(example), example.id)
      end

      # Every test this process defined, run or not, with its id and a name
      # telling it apart from other tests under that id.
      def defined_tests
        rspec_defined_tests + minitest_defined_tests
      end

      def rspec_defined_tests(rspec = rspec_module)
        return [] unless rspec

        rspec.world.all_examples.map { |example| [rspec_example_id(example), example.id] }
      end

      def minitest_defined_tests(root = Object)
        minitest_tests(root).map { |test_case, name| [minitest_id(test_case, name), minitest_name(test_case, name)] }
      end

      # Examples defined at one location, in a loop say, are told apart by
      # RSpec's id for each. Called as the suite starts, once every spec file
      # has loaded: a rerun loads whole files too, so it finds the same ones.
      def note_rspec_examples(examples)
        @shared_rspec_locations = repeated(examples.map { |example| example.metadata.fetch(:location) })
      end

      # Tests defined at one site, in a loop or in a module two test cases
      # include, are told apart by their names. Called as the suite starts, once
      # every test file has loaded, ahead of any worker a parallel executor forks.
      def note_minitest_tests(root = Object)
        @shared_minitest_sites = repeated(minitest_tests(root).map { |test_case, name| minitest_site(test_case, name) })
      end

      def repeated(values)
        values.tally.select { |_value, count| count > 1 }
      end

      # Each test method of each test case: its public `test_` methods, its
      # ancestors' included, as `Minitest::Test.runnable_methods` finds them.
      # That method itself shuffles them by `Minitest.seed`, which before the
      # suite starts is not set yet.
      def minitest_tests(root)
        minitest = loaded_const(root, :Minitest)
        test_case = minitest && loaded_const(minitest, :Test)
        return [] unless test_case

        minitest::Runnable.runnables.select { |runnable| runnable <= test_case }.flat_map do |runnable|
          runnable.public_instance_methods.grep(/\Atest_/) { |name| [runnable, name] }
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
      def install_minitest_hook(test_case = (Minitest::Test if defined?(Minitest::Test)), minitest = (Minitest if test_case))
        return if test_case.nil?

        test_case.prepend(MinitestRun)
        minitest.singleton_class.prepend(MinitestSuite)
      end

      # Installs the Minitest wrapper now when Minitest is already loaded, and
      # otherwise the moment `Minitest::Test` is defined. The deferred half is
      # what covers minitest 6 under the canonical helper ordering (SimpleCov
      # first, so coverage sees the app load; minitest after), where no plugin
      # ever fires. `root` is Object outside of tests.
      def install_minitest_hook_when_loaded(root = Object)
        minitest = loaded_const(root, :Minitest)
        test_case = minitest && loaded_const(minitest, :Test)
        return install_minitest_hook(test_case, minitest) if test_case
        return watch_for_minitest_test(minitest) if minitest

        ConstantWatch.new(:Minitest) do
          # `loaded_const` rather than the block capturing a module: the module
          # does not exist yet when the watch is armed.
          watch_for_minitest_test(loaded_const(root, :Minitest))
        end.attach(root)
      end

      # Relative the way RSpec prints it (`./spec/a_spec.rb:12` becomes
      # `spec/a_spec.rb:12`). A shared example's location is in the shared
      # group's file, and an example another example shares its location with
      # cannot be told apart by it, so either takes RSpec's id in its spec file
      # (`spec/a_spec.rb[1:2:1]`), which is its own and reruns it.
      def rspec_example_id(example)
        metadata = example.metadata
        location = metadata.fetch(:location)
        shared = !metadata.fetch(:shared_group_inclusion_backtrace).empty? || @shared_rspec_locations&.key?(location)
        rspec_path(shared ? example.id : location, metadata)
      end

      # RSpec writes a path relative to the directory it runs from
      # (`./spec/a_spec.rb`), or absolute for a file outside it. The same
      # metadata's absolute path for its own file says which directory that
      # is, so the path can be made relative to `SimpleCov.root` like every
      # other test id, whichever directory `rspec` ran from.
      def rspec_path(path, metadata)
        base = metadata.fetch(:absolute_file_path).delete_suffix(metadata.fetch(:file_path).delete_prefix("."))
        File.expand_path(path, base).delete_prefix(File.join(SimpleCov.root, ""))
      end

      # An autoload declaration fires `const_added` without the module existing
      # yet; that arrangement is left to the plugin, so nil means nothing to
      # watch.
      def watch_for_minitest_test(minitest)
        return unless minitest

        ConstantWatch.new(:Test) { install_minitest_hook(loaded_const(minitest, :Test), minitest) }.attach(minitest)
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
      # defined, relative to `SimpleCov.root`, with its name after it
      # (`test/a_test.rb:12[ATest#test_b]`) where tests share the site. Falls
      # back to `ClassName#method_name` when the method has no source location.
      def minitest_test_id(test)
        minitest_id(test.class, test.name)
      end

      def minitest_id(test_case, name)
        site = minitest_site(test_case, name)
        return minitest_name(test_case, name) unless site
        return site unless @shared_minitest_sites&.key?(site)

        "#{site}[#{minitest_name(test_case, name)}]"
      end

      def minitest_site(test_case, name)
        path, line = definition_site(test_case, name)
        "#{path.delete_prefix(File.join(SimpleCov.root, ""))}:#{line}" if path
      end

      def minitest_name(test_case, name)
        "#{test_case}##{name}"
      end

      # A method defined in C or through an eval without a filename has no site,
      # and a runner exotic enough to name a method it never defined deserves
      # an id over an exception out of the middle of its run.
      def definition_site(test_case, name)
        test_case.instance_method(name).source_location
      rescue NameError
        nil
      end
    end

    # Prepended to Minitest's singleton class by `install_minitest_hook`. The
    # suite starts running once every test file has loaded, so what runs
    # before the first test (a parallel executor setting up its workers, as
    # Rails' `parallelize_setup` does) belongs to no test, like RSpec's
    # `before(:suite)` hooks, rather than to the last test file loaded.
    module MinitestSuite
      def run(*)
        SimpleCov.test_tracker&.suite_starting
        TestTracker.note_minitest_tests
        super
      end
    end

    # Prepended to `Minitest::Test` by `install_minitest_hook`, wrapping each
    # test method run, setup and teardown included: a line only a setup block
    # reaches is still this test's line.
    module MinitestRun
      def run
        test_id = TestTracker.minitest_test_id(self)
        SimpleCov.test_tracker&.test_started(test_id, TestTracker.minitest_name(self.class, name))
        SimpleCov.track_test(test_id) { super }
      end
    end
  end
end
