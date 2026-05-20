# frozen_string_literal: true

require "helper"

# Make sure that exit codes of tests are propagated properly
# See https://github.com/simplecov-ruby/simplecov/issues/5
RSpec.describe "return codes" do # rubocop:disable RSpec/DescribeClass
  context "when inside fixtures/frameworks" do
    around do |test|
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "frameworks")) do
        FileUtils.rm_rf("./coverage")
        test.call
      end
    end

    let(:capture)         { Open3.capture3(env, command) }
    let(:env)             { {} }
    let(:captured_stderr) { capture[1] }
    let(:status)          { capture[2] }

    # SimpleCov writes its "Coverage report generated…" status line and
    # per-criterion totals to stderr by design. Strip those expected
    # lines so the "anything unusual on stderr?" assertions focus on
    # real diagnostic noise (errors, warnings, deprecations).
    def stderr_without_report_summary(stderr)
      stderr.lines.reject do |line|
        line.start_with?("Coverage report generated", "Line coverage:", "Branch coverage:", "Method coverage:")
      end.join
    end

    shared_examples "good tests" do
      it "has a zero exit status" do
        expect(status.exitstatus).to be_zero
      end

      it "prints nothing to STDERR aside from the coverage report summary" do
        expect(stderr_without_report_summary(captured_stderr)).to be_empty
      end
    end

    shared_examples "bad tests" do
      context "with default configuration" do
        it "has a non-zero exit status" do
          expect(status.exitstatus).not_to be_zero
        end

        it "prints a message to STDERR" do
          # https://github.com/oracle/truffleruby/issues/3535
          if RUBY_ENGINE == "truffleruby" &&
             Object::Object::RUBY_ENGINE_VERSION < "24.1" &&
             command.include?("testunit_bad.rb")
            skip "fails on truffleruby"
          end

          expect(captured_stderr).to match(/stopped.+SimpleCov.+previous.+error/i)
        end
      end

      context "when print_error_status is disabled" do
        let(:env) { super().merge("PRINT_ERROR_STATUS" => "false") }

        it "has a non-zero exit status" do
          expect(status.exitstatus).not_to be_zero
        end

        it "does not print error noise to STDERR (only the coverage report summary)" do
          expect(stderr_without_report_summary(captured_stderr)).to be_empty
        end
      end
    end

    context "when running testunit_good.rb" do
      let(:command) { "ruby testunit_good.rb" }

      it_behaves_like "good tests"
    end

    context "when running rspec_good.rb" do
      let(:command) { "rspec rspec_good.rb" }

      it_behaves_like "good tests"
    end

    context "when running testunit_bad.rb" do
      let(:command) { "ruby testunit_bad.rb" }

      it_behaves_like "bad tests"
    end

    context "when running rspec_bad.rb" do
      let(:command) { "rspec rspec_bad.rb" }

      it_behaves_like "bad tests"
    end
  end
end
