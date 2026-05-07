# frozen_string_literal: true

require "helper"

require "simplecov/formatter/multi_formatter"

describe SimpleCov::Formatter::MultiFormatter do
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
