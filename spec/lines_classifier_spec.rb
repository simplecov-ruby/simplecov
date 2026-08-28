# frozen_string_literal: true

require "helper"
require "simplecov/lines_classifier"
require "stringio"

RSpec.describe SimpleCov::LinesClassifier do
  subject(:classifier) { described_class.new }

  describe "#classify" do
    # `classify` walks its lines twice: once to find the directive-disabled
    # ranges, once to give each line a verdict. A source that can only be
    # read through once is the case that proves it materializes them first.
    it "classifies a stream of lines it can only read through once" do
      lines = StringIO.new("puts 'hi'\nputs 'there'\n").each_line

      classified = classifier.classify(lines)

      expect(classified.length).to eq(2)
      expect(classified).to all be_relevant
    end

    it "takes lines from anything that can list them, not only an array" do
      lines = %w[a=1 b=2].each

      expect(classifier.classify(lines).length).to eq(2)
    end

    describe "relevant lines" do
      it "determines code as relevant" do
        classified_lines = classifier.classify [
          "module Foo",
          "  class Baz",
          "    def Bar",
          "      puts 'hi'",
          "    end",
          "  end",
          "end"
        ]

        expect(classified_lines.length).to eq 7
        expect(classified_lines).to all be_relevant
      end

      it "determines invalid UTF-8 byte sequences as relevant" do
        classified_lines = classifier.classify [
          "bytes = \"\xF1t\xEBrn\xE2ti\xF4n\xE0liz\xE6ti\xF8n\""
        ]

        expect(classified_lines.length).to eq 1
        expect(classified_lines).to all be_relevant
      end
    end

    # `classify` reaches `no_cov_line?` only for lines that already passed
    # the whitespace-or-comment test, so an invalid byte sequence is caught
    # there first. `SourceFile::SkipChunks` calls this directly on raw
    # source, though, where it can still meet one.
    describe ".no_cov_line?" do
      it "is false for a line with an invalid UTF-8 byte sequence" do
        expect(described_class.no_cov_line?("# :nocov: \xF1\xEB\xE2")).to be(false)
      end

      it "is true for a well-formed marker" do
        expect(described_class.no_cov_line?("# :nocov:")).to be(true)
      end
    end

    # `classify_line` gates the marker match behind the whitespace-or-comment
    # test, which is only sound while every marker is also a comment. That
    # holds because `no_cov_line` is anchored `^(\s*)#`, strictly narrower than
    # `COMMENT_LINE`'s `^\s*#`. Loosening the marker to match a trailing
    # `x = 1 # :nocov:` would break the gate silently: the toggle would stop
    # firing and `:nocov:` blocks would stop being skipped, with nothing else
    # failing. This pins the implication so that change fails here instead.
    describe "the marker/comment invariant classify_line relies on" do
      markers = [
        "# :nocov:",
        "#:nocov:",
        "    # :nocov:",
        "\t#   :nocov:"
      ]

      markers.each do |line|
        it "treats #{line.inspect} as both a marker and a comment" do
          expect(described_class.no_cov_line?(line)).to be(true)
          expect(described_class.whitespace_line?(line)).to be(true)
        end
      end

      it "does not treat a trailing marker on a line of code as a marker" do
        # If this ever becomes true, `classify_line` needs to stop gating on
        # `whitespace_line?` before the change ships.
        expect(described_class.no_cov_line?("x = 1 # :nocov:")).to be(false)
      end
    end

    describe "not-relevant lines" do
      it "determines whitespace is not-relevant" do
        classified_lines = classifier.classify [
          "",
          "  ",
          "\t\t"
        ]

        expect(classified_lines.length).to eq 3
        expect(classified_lines).to all be_irrelevant
      end

      describe "comments" do
        it "determines comments are not-relevant" do
          classified_lines = classifier.classify [
            "#Comment",
            " # Leading space comment",
            "\t# Leading tab comment"
          ]

          expect(classified_lines.length).to eq 3
          expect(classified_lines).to all be_irrelevant
        end

        it "doesn't mistake interpolation as a comment" do
          classified_lines = classifier.classify [
            'puts "#{var}"' # rubocop:disable Lint/InterpolationCheck
          ]

          expect(classified_lines.length).to eq 1
          expect(classified_lines).to all be_relevant
        end
      end

      describe ":nocov: blocks" do
        it "determines :nocov: blocks are not-relevant" do
          classified_lines = classifier.classify [
            "# :nocov:",
            "def hi",
            "end",
            "# :nocov:"
          ]

          expect(classified_lines.length).to eq 4
          expect(classified_lines).to all be_irrelevant
        end

        it "determines all lines after a non-closing :nocov: as not-relevant" do
          classified_lines = classifier.classify [
            "# :nocov:",
            "puts 'Not relevant'",
            "# :nocov:",
            "puts 'Relevant again'",
            "puts 'Still relevant'",
            "# :nocov:",
            "puts 'Not relevant till the end'",
            "puts 'Ditto'"
          ]

          expect(classified_lines.length).to eq 8

          expect(classified_lines[0..2]).to all be_irrelevant
          expect(classified_lines[3..4]).to all be_relevant
          expect(classified_lines[5..7]).to all be_irrelevant
        end
      end

      # Named without a leading "#": mutant derives a subject expression
      # from the first token of an example's full description, and this
      # group sits under a class-named describe, so a leading "#" glues
      # into an expression nothing can parse and takes every example in
      # the group out of mutant's view.
      describe "the disable line and enable line directives" do
        it "marks lines inside a paired disable/enable block as not-relevant" do
          classified_lines = classifier.classify [
            "puts 'before'",
            "# simplecov:disable line",
            "puts 'inside 1'",
            "puts 'inside 2'",
            "# simplecov:enable line",
            "puts 'after'"
          ]

          expect(classified_lines[0]).to be_relevant
          expect(classified_lines[1..4]).to all be_irrelevant
          expect(classified_lines[5]).to be_relevant
        end

        it "treats an unclosed disable as running through end of file" do
          classified_lines = classifier.classify [
            "puts 'before'",
            "# simplecov:disable",
            "puts 'after 1'",
            "puts 'after 2'"
          ]

          expect(classified_lines[0]).to be_relevant
          expect(classified_lines[1..3]).to all be_irrelevant
        end

        it "applies inline disable to only the trailing line" do
          classified_lines = classifier.classify [
            "puts 'kept'",
            "raise 'absurd' # simplecov:disable",
            "puts 'kept too'"
          ]

          expect(classified_lines[0]).to be_relevant
          expect(classified_lines[1]).to be_irrelevant
          expect(classified_lines[2]).to be_relevant
        end

        it "does not affect line classification when only branch is disabled" do
          classified_lines = classifier.classify [
            "# simplecov:disable branch",
            "puts 'still relevant'",
            "# simplecov:enable branch"
          ]

          expect(classified_lines[1]).to be_relevant
        end
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

  # The lines are read twice, once to find the directives and once to
  # classify. A source that can only be read once is spent by the first
  # pass unless it is taken into an array first.
  it "classifies lines that can only be read once" do
    lines = Object.new.tap do |source|
      remaining = ["a = 1\n", "\n", "b = 2\n"]
      source.define_singleton_method(:each) { |&block| remaining.each(&block).tap { remaining = [] } }
      source.extend(Enumerable)
    end

    expect(classifier.classify(lines)).to eq([
                                               SimpleCov::LinesClassifier::RELEVANT,
                                               SimpleCov::LinesClassifier::NOT_RELEVANT,
                                               SimpleCov::LinesClassifier::RELEVANT
                                             ])
  end

  describe SimpleCov::LinesClassifier::SkipState do
    subject(:skip_state) { described_class.new }

    # Answered false rather than merely falsey: the state is a question
    # about the lines, and "not yet decided" is not one of its answers.
    it "starts outside a :nocov: pair" do
      expect(skip_state.skipping?).to be(false)
    end

    it "turns over, and back" do
      expect { skip_state.toggle }.to change(skip_state, :skipping?).from(false).to(true)
      expect { skip_state.toggle }.to change(skip_state, :skipping?).from(true).to(false)
    end
  end
end
