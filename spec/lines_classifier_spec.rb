require "helper"
require "simplecov/lines_classifier"

describe SimpleCov::LinesClassifier do
  describe "#classify" do
    describe "only relevant lines" do
      it "classifies each line as relevant" do
        classified_lines = subject.classify [
          "def foo",
          "end",
        ]

        expect(classified_lines.length).to eq 2
        expect(classified_lines).to all be_relevant
      end
    end

    describe "not-relevant lines" do
      it "classifies whitespace as not-relevant" do
        classified_lines = subject.classify [
          "",
          " ",
        ]

        expect(classified_lines.length).to eq 2
        expect(classified_lines).to all be_not_relevant
      end

      it "classifies comments as not-relevant" do
        classified_lines = subject.classify [
          "#Comment",
          " # Leading space comment",
        ]

        expect(classified_lines.length).to eq 2
        expect(classified_lines).to all be_not_relevant
      end

      it "classifies :nocov: blocks as not-relevant" do
        classified_lines = subject.classify [
          "# :nocov:",
          "def hi",
          "end",
          "# :nocov:",
        ]

        expect(classified_lines.length).to eq 4
        expect(classified_lines).to all be_not_relevant
      end
    end
  end

  RSpec::Matchers.define :be_relevant do
    match do |actual|
      actual == SimpleCov::LinesClassifier::RELEVANT
    end
  end

  RSpec::Matchers.define :be_not_relevant do
    match do |actual|
      actual == SimpleCov::LinesClassifier::NOT_RELEVANT
    end
  end
end
