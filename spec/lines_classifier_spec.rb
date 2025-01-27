# frozen_string_literal: true

require "helper"
require "simplecov/lines_classifier"

describe SimpleCov::LinesClassifier do
  describe "#classify" do
    describe "relevant lines" do
      it "determines code as relevant" do
        classified_lines = subject.classify [
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
        classified_lines = subject.classify [
          "bytes = \"\xF1t\xEBrn\xE2ti\xF4n\xE0liz\xE6ti\xF8n\""
        ]

        expect(classified_lines.length).to eq 1
        expect(classified_lines).to all be_relevant
      end
    end

    describe "not-relevant lines" do
      it "determines whitespace is not-relevant" do
        classified_lines = subject.classify [
          "",
          "  ",
          "\t\t"
        ]

        expect(classified_lines.length).to eq 3
        expect(classified_lines).to all be_irrelevant
      end

      describe "comments" do
        it "determines comments are not-relevant" do
          classified_lines = subject.classify [
            "#Comment",
            " # Leading space comment",
            "\t# Leading tab comment"
          ]

          expect(classified_lines.length).to eq 3
          expect(classified_lines).to all be_irrelevant
        end

        it "doesn't mistake interpolation as a comment" do
          classified_lines = subject.classify [
            'puts "#{var}"' # rubocop:disable Lint/InterpolationCheck
          ]

          expect(classified_lines.length).to eq 1
          expect(classified_lines).to all be_relevant
        end
      end

      describe ":nocov: one liner" do
        it "determines :nocov: lines are not-relevant" do
          classified_lines = subject.classify [
            "def hi",
            "raise NotImplementedError # :nocov:",
            "end",
            ""
          ]

          expect(classified_lines.length).to eq 4
          expect(classified_lines[1]).to be_irrelevant
        end
      end

      describe ":nocov: blocks" do
        it "determines :nocov: blocks are not-relevant" do
          classified_lines = subject.classify [
            "# :nocov:",
            "def hi",
            "end",
            "# :nocov:"
          ]

          expect(classified_lines.length).to eq 4
          expect(classified_lines).to all be_irrelevant
        end

        it "determines all lines after a non-closing :nocov: as not-relevant" do
          classified_lines = subject.classify [
            "puts 'Not relevant' # :nocov:",
            "# :nocov:",
            "puts 'Not relevant'",
            "# :nocov:",
            "puts 'Relevant again'",
            "puts 'Still relevant'",
            "# :nocov:",
            "puts 'Not relevant till the end' # :nocov:",
            "puts 'Ditto'"
          ]

          expect(classified_lines.length).to eq 9

          expect(classified_lines[0]).to be_irrelevant
          expect(classified_lines[1..3]).to all be_irrelevant
          expect(classified_lines[4..5]).to all be_relevant
          expect(classified_lines[6..8]).to all be_irrelevant
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
