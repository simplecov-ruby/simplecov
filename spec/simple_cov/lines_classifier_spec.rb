# frozen_string_literal: true

require "helper"
require "simplecov/lines_classifier"
require "stringio"

RSpec.describe SimpleCov::LinesClassifier do
  subject(:classifier) { described_class.new }

  let(:single_pass_source) do
    Object.new.tap do |source|
      remaining = ["a = 1\n", "\n", "b = 2\n"]
      source.define_singleton_method(:each) { |&block| remaining.each(&block).tap { remaining = [] } }
      source.extend(Enumerable)
    end
  end

  describe "#classify" do
    it "classifies a stream of lines it can only read through once" do
      lines = StringIO.new("puts 'hi'\nputs 'there'\n").each_line

      expect(classifier.classify(lines)).to match([be_relevant, be_relevant])
    end

    describe "relevant lines" do
      it "determines invalid UTF-8 byte sequences as relevant" do
        lines = ["bytes = \"\xF1t\xEBrn\xE2ti\xF4n\xE0liz\xE6ti\xF8n\""]

        expect(classifier.classify(lines)).to match([be_relevant])
      end
    end

    describe ".no_cov_line?" do
      it "is false for a line with an invalid UTF-8 byte sequence" do
        expect(described_class.no_cov_line?("# :nocov: \xF1\xEB\xE2")).to be(false)
      end

      it "is true for a well-formed marker" do
        expect(described_class.no_cov_line?("# :nocov:")).to be(true)
      end
    end

    describe "the marker/comment invariant classify_line relies on" do
      markers = [
        "# :nocov:",
        "#:nocov:",
        "    # :nocov:",
        "\t#   :nocov:"
      ]

      markers.each do |line|
        it "treats #{line.inspect} as a marker" do
          expect(described_class.no_cov_line?(line)).to be(true)
        end

        it "treats #{line.inspect} as a comment" do
          expect(described_class.whitespace_line?(line)).to be(true)
        end
      end
    end

    describe "not-relevant lines" do
      it "determines whitespace is not-relevant" do
        lines = ["", "  ", "\t\t"]

        expect(classifier.classify(lines)).to match([be_irrelevant, be_irrelevant, be_irrelevant])
      end
    end

    describe "not-relevant :nocov: blocks" do
      let(:closed_block) { ["# :nocov:", "def hi", "end", "# :nocov:"] }
      let(:reopened_block) do
        ["# :nocov:", "puts 'Not relevant'", "# :nocov:", "puts 'Relevant again'",
          "puts 'Still relevant'", "# :nocov:", "puts 'Not relevant till the end'", "puts 'Ditto'"]
      end

      it "determines :nocov: blocks are not-relevant" do
        expect(classifier.classify(closed_block)).to match(Array.new(4) { be_irrelevant })
      end

      it "determines all lines after a non-closing :nocov: as not-relevant" do
        expect(classifier.classify(reopened_block)).to match(
          [be_irrelevant, be_irrelevant, be_irrelevant, be_relevant,
            be_relevant, be_irrelevant, be_irrelevant, be_irrelevant]
        )
      end
    end

    describe "the not-relevant disable line and enable line directives" do
      let(:paired_block) do
        ["puts 'before'", "# simplecov:disable line", "puts 'inside 1'",
          "puts 'inside 2'", "# simplecov:enable line", "puts 'after'"]
      end
      let(:unclosed_block) do
        ["puts 'before'", "# simplecov:disable", "puts 'after 1'", "puts 'after 2'"]
      end
      let(:inline_disable) do
        ["puts 'kept'", "raise 'absurd' # simplecov:disable", "puts 'kept too'"]
      end
      let(:branch_only_block) do
        ["# simplecov:disable branch", "puts 'still relevant'", "# simplecov:enable branch"]
      end

      it "marks lines inside a paired disable/enable block as not-relevant" do
        expect(classifier.classify(paired_block)).to match(
          [be_relevant, be_irrelevant, be_irrelevant, be_irrelevant, be_irrelevant, be_relevant]
        )
      end

      it "treats an unclosed disable as running through end of file" do
        expect(classifier.classify(unclosed_block)).to match(
          [be_relevant, be_irrelevant, be_irrelevant, be_irrelevant]
        )
      end

      it "applies inline disable to only the trailing line" do
        expect(classifier.classify(inline_disable)).to match([be_relevant, be_irrelevant, be_relevant])
      end

      it "does not affect line classification when only branch is disabled" do
        expect(classifier.classify(branch_only_block)[1]).to be_relevant
      end
    end
  end

  RSpec::Matchers.define :be_relevant do
    match do |actual|
      actual == SimpleCov::LinesClassifier::RELEVANT
    end
  end

  RSpec::Matchers.define :be_irrelevant do
    match do |actual|
      actual == SimpleCov::LinesClassifier::NOT_RELEVANT
    end
  end

  it "classifies lines that can only be read once" do
    expect(classifier.classify(single_pass_source)).to match([be_relevant, be_irrelevant, be_relevant])
  end

  describe SimpleCov::LinesClassifier::SkipState do
    subject(:skip_state) { described_class.new }

    it "starts outside a :nocov: pair" do
      expect(skip_state.skipping?).to be(false)
    end

    it "turns over" do
      expect { skip_state.toggle }.to change(skip_state, :skipping?).from(false).to(true)
    end

    context "when already turned over" do
      before { skip_state.toggle }

      it "turns back" do
        expect { skip_state.toggle }.to change(skip_state, :skipping?).from(true).to(false)
      end
    end
  end
end
