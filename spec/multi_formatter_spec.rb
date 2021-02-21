# frozen_string_literal: true

require "helper"

require "simplecov/formatter/multi_formatter"

describe SimpleCov::Formatter::MultiFormatter do
  let(:children) do
    [
      SimpleCov::Formatter::SimpleFormatter,
      SimpleCov::Formatter::SimpleFormatter
    ]
  end

  describe ".new" do
    it "constructs a formatter with multiple children" do
      expect(described_class.new(children).new.formatters).to eq(children)
    end
  end

  describe ".[]" do
    # Regression test for https://github.com/simplecov-ruby/simplecov/issues/428
    it "constructs a formatter with multiple children" do
      result = nil
      expect { result = described_class[*children] }.to output(/DEPRECATION/).to_stderr

      expect(result.new.formatters).to eq(children)
    end
  end
end
