# frozen_string_literal: true

require "helper"

require "simplecov/formatter/multi_formatter"

RSpec.describe SimpleCov::Formatter::MultiFormatter do
  let(:result) { instance_double(SimpleCov::Result, command_name: "RSpec") }
  let(:good_formatter) do
    Class.new { def format(result) = "ok: #{result.command_name}" }
  end
  let(:bad_formatter) do
    Class.new { def format(_) = raise(ArgumentError, "boom") }
  end

  describe "#format" do
    it "hands the result to each formatter and collects what they return" do
      multi = described_class.new([good_formatter, good_formatter]).new

      expect(multi.format(result)).to eq(["ok: RSpec", "ok: RSpec"])
    end

    context "when one wrapped formatter raises" do
      let(:multi) { described_class.new([bad_formatter, good_formatter]).new }
      let(:formatted) do
        results = nil
        output = capture_stderr { results = multi.format(result) }
        [results, output]
      end
      let(:complaint) do
        file, line = bad_formatter.instance_method(:format).source_location
        line = (RUBY_ENGINE == "ruby") ? Regexp.escape(line.to_s) : "\\d+"
        /\AFormatter #{Regexp.escape(bad_formatter.to_s)} failed with ArgumentError: boom \
\(#{Regexp.escape(file)}:#{line}:[^)]*\)\n\z/
      end

      it "continues with the rest" do
        expect(formatted.first).to eq([nil, "ok: RSpec"])
      end

      it "names the formatter, the error and where it was raised" do
        expect(formatted.last).to match(complaint)
      end
    end

    it "lets an exception that is not a StandardError through" do
      exploding = Class.new { def format(_) = raise(NotImplementedError, "nope") }
      multi = described_class.new([exploding]).new

      expect { multi.format(result) }.to raise_error(NotImplementedError, "nope")
    end

    it "accepts formatter instances alongside classes" do
      multi = described_class.new([good_formatter, good_formatter.new]).new

      expect(multi.format(result)).to eq(["ok: RSpec", "ok: RSpec"])
    end
  end

  it "wraps a lone formatter that was not given as a list" do
    multi = described_class.new(good_formatter).new

    expect(multi.format(result)).to eq(["ok: RSpec"])
  end

  it "formats nothing at all when constructed without formatters" do
    multi = described_class.new.new

    expect(multi.format(result)).to eq([])
  end
end
