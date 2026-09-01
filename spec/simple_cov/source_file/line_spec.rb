# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::SourceFile::Line do
  context "when a source line" do
    subject(:line) do
      described_class.new("# the ruby source", 5, 3)
    end

    it 'returns "# the ruby source" as src' do
      expect(line.src).to eq("# the ruby source")
    end

    it "returns the same for source as for src" do
      expect(line.src).to eq(line.source)
    end

    it "has line number 5" do
      expect(line.line_number).to eq(5)
    end

    it "answers the same for line as for line_number" do
      expect(line.line).to eq(line.line_number)
    end

    it "answers the same for number as for line_number" do
      expect(line.number).to eq(line.line_number)
    end

    context "when flagged as skipped!" do
      before do
        line.skipped!
      end

      it "is not covered" do
        expect(line).not_to be_covered
      end

      it "is skipped" do
        expect(line).to be_skipped
      end

      it "is not missed" do
        expect(line).not_to be_missed
      end

      it "is not never" do
        expect(line).not_to be_never
      end

      it "status is skipped" do
        expect(line.status).to eq("skipped")
      end
    end
  end

  context "when A source line with coverage" do
    subject(:line) do
      described_class.new("# the ruby source", 5, 3)
    end

    it "has coverage of 3" do
      expect(line.coverage).to eq(3)
    end

    it "is covered" do
      expect(line).to be_covered
    end

    it "is not skipped" do
      expect(line).not_to be_skipped
    end

    it "is not missed" do
      expect(line).not_to be_missed
    end

    it "is not never" do
      expect(line).not_to be_never
    end

    it "status is covered" do
      expect(line.status).to eq("covered")
    end
  end

  context "when A source line without coverage" do
    subject(:line) do
      described_class.new("# the ruby source", 5, 0)
    end

    it "has coverage of 0" do
      expect(line.coverage).to be_zero
    end

    it "is not covered" do
      expect(line).not_to be_covered
    end

    it "is not skipped" do
      expect(line).not_to be_skipped
    end

    it "is missed" do
      expect(line).to be_missed
    end

    it "is not never" do
      expect(line).not_to be_never
    end

    it "status is missed" do
      expect(line.status).to eq("missed")
    end
  end

  context "when A source line with no code" do
    subject(:line) do
      described_class.new("# the ruby source", 5, nil)
    end

    it "has nil coverage" do
      expect(line.coverage).to be_nil
    end

    it "is not covered" do
      expect(line).not_to be_covered
    end

    it "is not skipped" do
      expect(line).not_to be_skipped
    end

    it "is not missed" do
      expect(line).not_to be_missed
    end

    it "is never" do
      expect(line).to be_never
    end

    it "status is never" do
      expect(line.status).to eq("never")
    end
  end

  context "when a skipped line" do
    it "is not covered, though it was hit" do
      line = described_class.new("# the ruby source", 5, 3).tap(&:skipped!)

      expect(line).to have_attributes(covered?: false, status: "skipped")
    end

    it "is not missed, though it was never hit" do
      line = described_class.new("# the ruby source", 5, 0).tap(&:skipped!)

      expect(line).to have_attributes(missed?: false, status: "skipped")
    end

    it "is not never, though it carries no coverage" do
      line = described_class.new("# the ruby source", 5, nil).tap(&:skipped!)

      expect(line).to have_attributes(never?: false, status: "skipped")
    end
  end

  it "starts out unskipped" do
    line = described_class.new("# the ruby source", 5, 3)

    expect(line).to have_attributes(skipped: false, skipped?: false)
  end

  it "accepts a String subclass as its source" do
    subclass = Class.new(String)

    expect(described_class.new(subclass.new("some source"), 5, 3).src).to eq("some source")
  end

  describe "a line number and a coverage that answer to Integer" do
    let(:integer_like) do
      Class.new do
        def is_a?(klass)
          klass.equal?(Integer)
        end
      end
    end
    let(:line_number) { integer_like.new }
    let(:coverage) { integer_like.new }
    let(:line) { described_class.new("some source", line_number, coverage) }

    it "is accepted as the line number" do
      expect(line.line_number).to be(line_number)
    end

    it "is accepted as the coverage" do
      expect(line.coverage).to be(coverage)
    end
  end

  it "raises ArgumentError when initialized with invalid src" do
    expect { described_class.new(:symbol, 5, 3) }
      .to raise_error(ArgumentError, "Only String accepted for source")
  end

  it "raises ArgumentError when initialized with invalid line_number" do
    expect { described_class.new("some source", "five", 3) }
      .to raise_error(ArgumentError, "Only Integer accepted for line_number")
  end

  it "raises ArgumentError when initialized with invalid coverage" do
    expect { described_class.new("some source", 5, "three") }
      .to raise_error(ArgumentError, "Only Integer and nil accepted for coverage")
  end
end
