# frozen_string_literal: true

require "helper"
require "simplecov/lines_classifier"

describe SimpleCov::LinesClassifier do
  subject(:classifier) { described_class.new }

  describe "#classify" do
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

      describe "# simplecov:disable line / enable line directives" do
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
end
