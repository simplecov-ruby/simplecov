# frozen_string_literal: true

require "helper"
require "simplecov/test_contexts/hooks"

RSpec.describe SimpleCov::TestContexts::Hooks do
  around do |example|
    described_class.reset!
    example.run
  ensure
    described_class.reset!
  end

  describe ".install_rspec!" do
    let(:config) { instance_double(RSpec::Core::Configuration) }

    def install_and_capture_hook
      hook = nil
      allow(config).to receive(:around).with(:each) { |&block| hook = block }
      described_class.install_rspec!(config)
      hook
    end

    it "wraps examples through the recorder" do
      hook = install_and_capture_hook
      recorder = instance_double(SimpleCov::TestContexts::Recorder)
      allow(SimpleCov).to receive(:test_context_recorder).and_return(recorder)
      allow(recorder).to receive(:record).and_yield
      example = instance_double(RSpec::Core::Example::Procsy,
                                id: "./spec/x_spec.rb[1:1]", full_description: "X does a thing")
      allow(example).to receive(:run)

      hook.call(example)

      expect(recorder).to have_received(:record).with("./spec/x_spec.rb[1:1]", "X does a thing")
      expect(example).to have_received(:run)
    end

    it "passes examples through untouched without a recorder" do
      hook = install_and_capture_hook
      allow(SimpleCov).to receive(:test_context_recorder).and_return(nil)
      example = instance_double(RSpec::Core::Example::Procsy)
      allow(example).to receive(:run)

      hook.call(example)

      expect(example).to have_received(:run)
    end

    it "installs only once" do
      install_and_capture_hook
      second_config = instance_double(RSpec::Core::Configuration)
      allow(second_config).to receive(:around)

      described_class.install_rspec!(second_config)

      expect(second_config).not_to have_received(:around)
    end
  end

  describe ".install_minitest!" do
    let(:target) do
      Class.new do
        attr_reader :ran

        def run
          @ran = true
          :from_super
        end

        def name
          "test_something"
        end
      end
    end

    it "prepends a wrapper that records around #run" do
      described_class.install_minitest!(target)
      recorder = instance_double(SimpleCov::TestContexts::Recorder)
      allow(SimpleCov).to receive(:test_context_recorder).and_return(recorder)
      allow(recorder).to receive(:record).and_yield

      instance = target.new
      expect(instance.run).to eq :from_super
      expect(instance.ran).to be true
      expect(recorder).to have_received(:record).with(/#test_something\z/)
    end

    it "runs tests untouched without a recorder" do
      described_class.install_minitest!(target)
      allow(SimpleCov).to receive(:test_context_recorder).and_return(nil)

      instance = target.new
      expect(instance.run).to eq :from_super
      expect(instance.ran).to be true
    end

    it "installs only once" do
      described_class.install_minitest!(target)
      described_class.install_minitest!(target)

      wrapper = described_class::MinitestRun
      expect(target.ancestors.count { |mod| mod == wrapper }).to eq 1
    end
  end

  describe ".install!" do
    it "installs the hooks of the loaded frameworks" do
      stub_const("Minitest::Test", Class.new)
      allow(described_class).to receive(:install_rspec!)
      allow(described_class).to receive(:install_minitest!)

      described_class.install!

      expect(described_class).to have_received(:install_rspec!).with(no_args)
      expect(described_class).to have_received(:install_minitest!).with(no_args)
    end

    it "arms the const watcher when Minitest is not loaded yet" do
      hide_const("Minitest")
      allow(described_class).to receive(:install_rspec!)
      allow(described_class).to receive(:watch_for_minitest!)

      described_class.install!

      expect(described_class).to have_received(:watch_for_minitest!)
    end
  end

  describe ".watch_for_minitest!" do
    it "installs the hook the moment Minitest::Test gets defined" do
      hide_const("Minitest")
      described_class.watch_for_minitest!

      stub_const("Minitest", Module.new)
      expect(described_class.installed_minitest?).to be false

      Minitest.const_set(:Test, Class.new)

      expect(described_class.installed_minitest?).to be true
      expect(Minitest::Test.ancestors).to include(described_class::MinitestRun)
    end

    it "watches Minitest directly when the module exists without Test" do
      stub_const("Minitest", Module.new)
      described_class.watch_for_minitest!

      Minitest.const_set(:Test, Class.new)

      expect(described_class.installed_minitest?).to be true
    end

    it "arms only once" do
      hide_const("Minitest")
      described_class.watch_for_minitest!
      described_class.watch_for_minitest!

      stub_const("Minitest", Module.new)
      Minitest.const_set(:Test, Class.new)

      expect(Minitest::Test.ancestors.count { |mod| mod == described_class::MinitestRun }).to eq 1
    end

    it "ignores unrelated constants" do
      hide_const("Minitest")
      described_class.watch_for_minitest!

      stub_const("SomethingUnrelated", Module.new)

      expect(described_class.installed_minitest?).to be false
    end

    it "stays inert after reset!" do
      hide_const("Minitest")
      described_class.watch_for_minitest!
      described_class.reset!

      stub_const("Minitest", Module.new)
      Minitest.const_set(:Test, Class.new)

      expect(described_class.installed_minitest?).to be false
    end

    it "leaves a pending Minitest autoload unloaded and hooks when it resolves" do
      hide_const("Minitest")
      described_class.watch_for_minitest!

      dir = Dir.mktmpdir("simplecov-autoload-spec-")
      fake = File.join(dir, "fake_minitest.rb")
      File.write(fake, <<~RUBY)
        module Minitest
          class Test
          end
        end
      RUBY

      # Declaring the autoload fires const_added; the watcher must not
      # force the require on the spot.
      Object.autoload(:Minitest, fake)
      expect(described_class.installed_minitest?).to be false

      Object.const_get(:Minitest) # resolve the autoload

      expect(described_class.installed_minitest?).to be true
      expect(Minitest::Test.ancestors).to include(described_class::MinitestRun)
    ensure
      # rubocop:disable RSpec/RemoveConst -- clears the pending autoload
      # (or its resolved fake); stub_const cannot manage autoload entries
      Object.send(:remove_const, :Minitest) if Object.const_defined?(:Minitest)
      # rubocop:enable RSpec/RemoveConst
      FileUtils.remove_entry(dir) if dir
    end

    it "stays deferred when const_added fires before the constant resolves, as JRuby's autoload declaration does" do
      hide_const("Minitest")
      described_class.watch_for_minitest!

      described_class.on_const_added(Object, :Minitest)

      expect(described_class.installed_minitest?).to be false
    end
  end

  describe ".installed_any?" do
    it "is false before any installation" do
      expect(described_class.installed_any?).to be false
    end

    it "is true once the RSpec hook is installed" do
      config = instance_double(RSpec::Core::Configuration, around: nil)
      described_class.install_rspec!(config)

      expect(described_class.installed_any?).to be true
    end

    it "is true once the Minitest hook is installed" do
      described_class.install_minitest!(Class.new)

      expect(described_class.installed_any?).to be true
    end
  end
end
