# frozen_string_literal: true

require "helper"

describe SimpleCov::SimulateCoverage do
  describe ".call" do
    let(:fixture) { source_fixture("sample.rb") }

    it "produces a hash with lines/branches/methods keys" do
      result = described_class.call(fixture)
      expect(result.keys).to contain_exactly("lines", "branches", "methods")
    end

    it "classifies the file's lines via LinesClassifier" do
      result = described_class.call(fixture)
      expect(result["lines"]).to be_an(Array)
      expect(result["lines"]).not_to be_empty
    end

    it "returns empty branches and methods (we never parse them)" do
      result = described_class.call(fixture)
      expect(result["branches"]).to eq({})
      expect(result["methods"]).to eq({})
    end
  end
end
