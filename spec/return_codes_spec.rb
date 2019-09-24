# frozen_string_literal: true

require "helper"

# Make sure that exit codes of tests are propagated properly
# See https://github.com/colszowka/simplecov/issues/5
describe "return codes" do
  context "inside fixtures/frameworks" do
    around do |test|
      Dir.chdir(File.join(File.dirname(__FILE__), "fixtures", "frameworks")) do
        FileUtils.rm_rf("./coverage")
        test.call
      end
    end

    before do
      @stdout, @stderr, @status = Open3.capture3(command)
    end

    shared_examples "good tests" do
      it "has a zero exit status" do
        expect(@status.exitstatus).to be_zero
      end

      it "prints nothing to STDERR" do
        expect(@stderr).to be_empty
      end
    end

    shared_examples "bad tests" do
      context "with default configuration" do
        it "has a non-zero exit status" do
          expect(@status.exitstatus).not_to be_zero
        end

        it "prints a message to STDERR" do
          expect(@stderr).to eq "SimpleCov failed with exit #{@status.exitstatus}\n"
        end
      end

      context "when print_error_status is disabled" do
        let(:command) { "PRINT_ERROR_STATUS=false " + super() }

        it "has a non-zero exit status" do
          expect(@status.exitstatus).not_to be_zero
        end

        it "does not print anything to STDERR" do
          expect(@stderr).to be_empty
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
