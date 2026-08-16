# frozen_string_literal: true

module SimpleCov
  module TestContexts
    # Installs the per-framework wrappers that funnel each test through
    # `SimpleCov.test_context_recorder`. The wrappers re-read the
    # recorder per test, so a nil recorder makes them passthroughs.
    module Hooks
      # Prepended to `Minitest::Test` so each test's `run` is recorded
      # under its `Class#name` rerun id.
      module MinitestRun
        def run
          recorder = SimpleCov.test_context_recorder
          return super unless recorder

          recorder.record("#{self.class}##{name}") { super }
        end
      end

      # Waits for `Minitest::Test` to be defined: SimpleCov usually
      # starts before Minitest is required, and Minitest 6 no longer
      # loads plugins on its own, so nothing else would call back in.
      module MinitestConstWatcher
        def const_added(name)
          super
          SimpleCov::TestContexts::Hooks.on_const_added(self, name)
        end
      end

      class << self
        def install!
          # simplecov:disable branch — which frameworks are loaded is an
          # environment fact this suite cannot vary
          install_rspec! if defined?(::RSpec) && ::RSpec.respond_to?(:configure)
          if defined?(::Minitest::Test)
            install_minitest!
          else
            watch_for_minitest!
          end
          # simplecov:enable
        end

        def watch_for_minitest!
          return if @watching_minitest

          @watching_minitest = true
          if defined?(::Minitest)
            ::Minitest.singleton_class.prepend(MinitestConstWatcher)
          else
            ::Object.singleton_class.prepend(MinitestConstWatcher)
          end
        end

        def on_const_added(owner, name)
          return unless @watching_minitest
          return if owner.autoload?(name)

          if owner == ::Object && name == :Minitest
            ::Minitest.singleton_class.prepend(MinitestConstWatcher)
          elsif minitest_test_appeared?(owner, name)
            @watching_minitest = false
            install_minitest!
          end
        end

        def minitest_test_appeared?(owner, name)
          defined?(::Minitest) && owner == ::Minitest && name == :Test
        end

        def installed_any?
          installed_rspec? || installed_minitest?
        end

        def installed_rspec?
          @rspec_installed
        end

        def installed_minitest?
          @minitest_installed
        end

        def install_rspec!(config = ::RSpec.configuration)
          return if installed_rspec?

          @rspec_installed = true
          config.around(:each) do |example|
            recorder = SimpleCov.test_context_recorder
            if recorder
              recorder.record(example.id, example.full_description) { example.run }
            else
              example.run
            end
          end
        end

        def install_minitest!(target = ::Minitest::Test)
          return if installed_minitest?

          @minitest_installed = true
          target.prepend(MinitestRun)
        end

        def reset!
          @rspec_installed = false
          @minitest_installed = false
          @watching_minitest = false
        end
      end

      reset!
    end
  end
end
