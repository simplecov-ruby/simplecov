# frozen_string_literal: true

require "helper"

describe SimpleCov::SourceFile::Line do
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

    it "has equal line_number, line and number" do
      expect(line.line).to eq(line.line_number)
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

  it "raises ArgumentError when initialized with invalid src" do
    expect { described_class.new(:symbol, 5, 3) }.to raise_error(ArgumentError)
  end

  it "raises ArgumentError when initialized with invalid line_number" do
    expect { described_class.new("some source", "five", 3) }.to raise_error(ArgumentError)
  end

  it "raises ArgumentError when initialized with invalid coverage" do
    expect { described_class.new("some source", 5, "three") }.to raise_error(ArgumentError)
  end
end
