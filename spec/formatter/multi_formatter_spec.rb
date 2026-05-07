# frozen_string_literal: true

require "helper"

require "simplecov/formatter/multi_formatter"

describe SimpleCov::Formatter::MultiFormatter do
  describe ".[]" do
    # Regression test for https://github.com/simplecov-ruby/simplecov/issues/428
    it "constructs a formatter with multiple children" do
      # Silence deprecation warnings.
      allow(described_class).to receive(:warn)

      children = [
        SimpleCov::Formatter::SimpleFormatter,
        SimpleCov::Formatter::SimpleFormatter
      ]

      expect(described_class[*children].new.formatters).to eq(children)
    end
  end

  describe "#format" do
    let(:result) { instance_double(SimpleCov::Result) }
    let(:good_formatter) { Class.new { def format(_) = "ok" } }
    let(:bad_formatter) do
      Class.new { def format(_) = raise StandardError, "boom" }
    end

    it "rescues errors from individual wrapped formatters and continues with the rest" do
      multi = described_class.new([bad_formatter, good_formatter]).new
      results = nil
      output = capture_stderr { results = multi.format(result) }
      expect(results).to eq([nil, "ok"])
      expect(output).to match(/Formatter .* failed with StandardError: boom/)
    end
  end
end
