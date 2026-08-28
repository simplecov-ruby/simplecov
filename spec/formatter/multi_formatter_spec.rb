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

    it "rescues errors from individual wrapped formatters and continues with the rest" do
      multi = described_class.new([bad_formatter, good_formatter]).new
      file, line = bad_formatter.instance_method(:format).source_location
      results = nil

      output = capture_stderr { results = multi.format(result) }

      expect(results).to eq([nil, "ok: RSpec"])
      # The whole line, including the frame that raised: the first frame
      # is the formatter's own, which is the one worth naming. Engines
      # disagree on which line the frame carries, so only CRuby pins it.
      line = RUBY_ENGINE == "ruby" ? Regexp.escape(line.to_s) : "\\d+"
      expect(output).to match(
        /\AFormatter #{Regexp.escape(bad_formatter.to_s)} failed with ArgumentError: boom \
\(#{Regexp.escape(file)}:#{line}:[^)]*\)\n\z/
      )
    end

    # Only the errors a formatter can reasonably raise are absorbed. An
    # Exception that isn't a StandardError (a signal, an exhausted
    # machine) has to keep travelling.
    it "lets an exception that is not a StandardError through" do
      exploding = Class.new { def format(_) = raise(NotImplementedError, "nope") }
      multi = described_class.new([exploding]).new

      expect { multi.format(result) }.to raise_error(NotImplementedError, "nope")
    end

    # Instances carry constructor options (e.g. `silent: true`) that
    # classes can't; see #1240.
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
