# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::ExitCodes do
  describe SimpleCov::ExitCodes::Check, mutant_expression: "SimpleCov::ExitCodes::Check*" do
    let(:check_class) do
      Class.new(described_class) do
        def exit_code = 2

        def computed
          @computed ||= 0
        end

        private

        def compute_violations
          @computed = computed + 1
          [{name: "first"}, {name: "second"}]
        end

        def violation_lines(violation)
          ["line for #{violation.fetch(:name)}"]
        end
      end
    end
    let(:check) { check_class.new(instance_double(SimpleCov::Result), nil) }

    it "answers its violations as values, computed once however often they are asked for" do
      expect(check.violations).to eq([{name: "first"}, {name: "second"}])
      expect(check.violations).to eq([{name: "first"}, {name: "second"}])
      expect(check.computed).to eq(1)
    end

    it "renders its whole report as values, every violation's lines in order" do
      expect(check.report_lines).to eq(["line for first", "line for second"])
    end

    it "is failing exactly when it holds violations" do
      expect(check).to be_failing
    end

    it "stashes the result and the thresholds for its subclasses to read" do
      quiet = Class.new(described_class) do
        def stashed = [result, thresholds]
      end

      expect(quiet.new(:the_result, :the_thresholds).stashed).to eq(%i[the_result the_thresholds])
    end

    context "when nothing violates" do
      let(:check) do
        empty_class = Class.new(described_class) do
          private

          def compute_violations = []
        end
        empty_class.new(instance_double(SimpleCov::Result), nil)
      end

      it "answers exactly false rather than the empty list it holds" do
        expect(check.failing?).to be(false)
      end

      it "renders nothing" do
        expect(check.report_lines).to eq([])
      end

      it "prints nothing" do
        allow(SimpleCov::ExitCodes).to receive(:print_error)

        check.report

        expect(SimpleCov::ExitCodes).not_to have_received(:print_error)
      end
    end

    it "answers exactly true when something violates" do
      expect(check.failing?).to be(true)
    end

    it "prints exactly its rendered lines, through the enforcement printer, in order" do
      allow(SimpleCov::ExitCodes).to receive(:print_error)

      check.report

      expect(SimpleCov::ExitCodes).to have_received(:print_error).with("line for first").ordered
      expect(SimpleCov::ExitCodes).to have_received(:print_error).with("line for second").ordered
    end
  end

  describe ".print_error" do
    it "writes the message to stderr" do
      expect(capture_stderr { described_class.print_error("boom") }).to eq("boom\n")
    end

    it "stays quiet when stderr was closed before at_exit (e.g. by rspec-conductor)" do
      allow($stderr).to receive(:puts).and_raise(IOError, "closed stream")

      expect { described_class.print_error("boom") }.not_to raise_error
    end
  end
end
