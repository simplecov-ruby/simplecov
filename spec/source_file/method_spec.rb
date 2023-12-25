# frozen_string_literal: true

require "helper"

describe SimpleCov::SourceFile::Method do
  subject { described_class.new(source_file, info, coverage) }

  let(:source_file) do
    SimpleCov::SourceFile.new(source_fixture("methods.rb"), lines: {})
  end

  let(:info) { ["A", :method1, 2, 2, 5, 5] }
  let(:coverage) { 1 }

  it "is covered" do
    expect(subject.covered?).to eq(true)
  end

  it "is not skipped" do
    expect(subject.skipped?).to eq(false)
  end

  it "is not missed" do
    expect(subject.missed?).to eq(false)
  end

  it "has 4 lines" do
    expect(subject.lines.size).to eq(4)
  end

  it "converts to string properly" do
    expect(subject.to_s).to eq("A#method1")
  end

  context "uncovered method" do
    let(:coverage) { 0 }

    it "is not covered" do
      expect(subject.covered?).to eq(false)
    end

    it "is not skipped" do
      expect(subject.skipped?).to eq(false)
    end

    it "is missed" do
      expect(subject.missed?).to eq(true)
    end
  end
end
