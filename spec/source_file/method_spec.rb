# frozen_string_literal: true

require "helper"

describe SimpleCov::SourceFile::Method do
  subject(:the_method) { described_class.new(source_file, info, coverage) }

  let(:source_file) do
    SimpleCov::SourceFile.new(source_fixture("methods.rb"), {"lines" => {}})
  end

  let(:info) { ["A", :method1, 2, 2, 5, 5] }
  let(:coverage) { 1 }

  it "is covered" do
    expect(the_method.covered?).to be(true)
  end

  it "is not skipped" do
    expect(the_method.skipped?).to be(false)
  end

  it "is not missed" do
    expect(the_method.missed?).to be(false)
  end

  it "has 4 lines" do
    expect(the_method.lines.size).to eq(4)
  end

  it "converts to string properly" do
    expect(the_method.to_s).to eq("A#method1")
  end

  context "with nil line info" do
    let(:info) { ["A", :method1, nil, nil, nil, nil] }

    it "returns empty lines" do
      expect(the_method.lines).to eq([])
    end

    it "is skipped" do
      expect(the_method.skipped?).to be(true)
    end
  end

  context "when uncovered method" do
    let(:coverage) { 0 }

    it "is not covered" do
      expect(the_method.covered?).to be(false)
    end

    it "is not skipped" do
      expect(the_method.skipped?).to be(false)
    end

    it "is missed" do
      expect(the_method.missed?).to be(true)
    end
  end

  describe "#skipped!" do
    it "marks the method as skipped regardless of its line coverage" do
      the_method.skipped!

      expect(the_method.skipped?).to be true
      expect(the_method.covered?).to be false
      expect(the_method.missed?).to be false
    end
  end

  describe "#overlaps_with?" do
    it "is true when the method's range intersects the given range" do
      expect(the_method.overlaps_with?(3..4)).to be true
      expect(the_method.overlaps_with?(1..2)).to be true
      expect(the_method.overlaps_with?(5..7)).to be true
    end

    it "is false when the method's range sits entirely outside the given range" do
      expect(the_method.overlaps_with?(6..10)).to be false
      expect(the_method.overlaps_with?(0..1)).to be false
    end

    context "with nil line info" do
      let(:info) { ["A", :method1, nil, nil, nil, nil] }

      it "is false" do
        expect(the_method.overlaps_with?(1..10)).to be false
      end
    end
  end
end
