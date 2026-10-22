# frozen_string_literal: true

require "helper"
require "support/sandbox_project"

RSpec.describe "track_tests", :sandbox do
  let(:tracking_config) do
    <<~RUBY
      require 'simplecov'
      SimpleCov.start do
        track_tests
      end
    RUBY
  end

  before { setup_project("faked_project") }

  def stored_contexts
    resultset = resultset_json
    expect(resultset.size).to eq(1)
    map = resultset.values.first["contexts"]
    expect(map).not_to be_nil
    SimpleCov::ContextMap.from_hash(map)
  end

  describe "an RSpec suite" do
    before do
      write_file("lib/lazy.rb", <<~RUBY)
        class Lazy
          def call
            :called
          end

          def short?(flag) = (flag || call) && true
        end
      RUBY
      write_file("spec/zz_defining_spec.rb", <<~RUBY)
        require "spec_helper"

        RSpec.describe "Defining" do
          it("defines an example from \#{FakedProject.foo}") { expect(1).to eq(1) }
        end
      RUBY
      write_file("spec/lazy_spec.rb", <<~RUBY)
        require "spec_helper"

        RSpec.describe "Lazy" do
          it "loads it and calls it" do
            require_relative "../lib/lazy"
            expect(Lazy.new.short?(false)).to be(true)
          end
        end
      RUBY
    end

    let!(:result) do
      configure_simplecov(:rspec, tracking_config)
      run_command_and_expect_success(sorted_rspec_command)
    end
    let(:some_class) { File.join(sandbox_dir, "lib/faked_project/some_class.rb") }

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "records each example as a context" do
      expect(stored_contexts.contexts).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
    end

    it "records each example against the lines it covered" do
      expect(stored_contexts.covering(some_class, 12)).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
    end

    it "credits a test with the method body it ran in a file it loaded" do
      expect(stored_contexts.covering(File.join(sandbox_dir, "lib/lazy.rb"), 3))
        .to eq(["spec/lazy_spec.rb:4"])
    end

    it "credits a test with a one-line method it ran in a file it loaded" do
      expect(stored_contexts.covering(File.join(sandbox_dir, "lib/lazy.rb"), 6))
        .to eq(["spec/lazy_spec.rb:4"])
    end

    it "credits a spec file with what it ran while it loaded" do
      expect(stored_contexts.covering(File.join(sandbox_dir, "lib/faked_project.rb"), 5))
        .to include("spec/zz_defining_spec.rb")
    end

    it "leaves the lines a file ran as it loaded to no test" do
      expect(stored_contexts.covering(File.join(sandbox_dir, "lib/lazy.rb"), 1)).to eq([])
    end

    context "when a later run reruns one spec file" do
      before { run_command_and_expect_success("bundle exec rspec spec/lazy_spec.rb") }

      it "keeps the tests of the spec files it did not rerun" do
        expect(stored_contexts.covering(some_class, 12)).to include(match(%r{\Aspec/some_class_spec\.rb:\d+\z}))
      end

      it "keeps the tests of the spec file it reran" do
        expect(stored_contexts.covering(File.join(sandbox_dir, "lib/lazy.rb"), 3)).to eq(["spec/lazy_spec.rb:4"])
      end
    end
  end

  describe "a Minitest suite" do
    let!(:result) do
      self.bundle_with = "minitest"
      install_dependencies
      configure_simplecov(:minitest, tracking_config)
      run_command_and_expect_success("bundle exec rake minitest")
    end

    it "generates a report" do
      expect_coverage_report_generated(result)
    end

    it "records each test as a context" do
      expect(stored_contexts.contexts).to include(match(%r{\Aminitest/some_test\.rb:\d+\z}))
    end
  end

  describe "a Minitest suite whose parallel executor sets up workers before any test" do
    before do
      self.bundle_with = "minitest"
      install_dependencies
      write_file("lib/worker_setup.rb", <<~RUBY)
        module WorkerSetup
          def self.prepare
            :prepared
          end
        end
      RUBY
      write_file("minitest/aa_setup_test.rb", <<~RUBY)
        require "test_helper"
        require "delegate"
        require_relative "../lib/worker_setup"

        class PreparingExecutor < SimpleDelegator
          def start
            WorkerSetup.prepare
            super if __getobj__.respond_to?(:start)
          end
        end
        Minitest.parallel_executor = PreparingExecutor.new(Minitest.parallel_executor)

        class AaSetupTest < Minitest::Test
          def test_nothing = assert(true)
        end
      RUBY
      configure_simplecov(:minitest, tracking_config)
      run_command_and_expect_success("bundle exec rake minitest")
    end

    it "leaves the setup to no test, like RSpec's before(:suite)" do
      expect(stored_contexts.covering(File.join(sandbox_dir, "lib/worker_setup.rb"), 3)).to eq([])
    end
  end

  describe "a Minitest suite whose tests run concurrently in threads" do
    before do
      self.bundle_with = "minitest"
      install_dependencies
      write_file("minitest/threaded_test.rb", <<~RUBY)
        require "test_helper"

        class ThreadedTest < Minitest::Test
          parallelize_me!

          def test_one = sleep(0.2)
          def test_two = sleep(0.2)
        end
      RUBY
      configure_simplecov(:minitest, tracking_config)
      run_command_and_expect_success("bundle exec rake minitest")
    end

    it "says why the report carries no test map" do
      status = run_command_and_expect_success("bundle exec simplecov status --input coverage/coverage.json")

      expect(status.output).to include("tests recorded: none (dropped because tests ran concurrently in threads")
    end
  end
end
