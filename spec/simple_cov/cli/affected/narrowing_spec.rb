# frozen_string_literal: true

require "helper"
require "simplecov/cli"

RSpec.describe SimpleCov::CLI::Affected::Narrowing, :prism do
  let(:source) do
    <<~RUBY
      class Widget
        def small = :small

        def large
          def inner
            :inner
          end
          :large
        end
      end
    RUBY
  end

  describe ".mask" do
    it "masks the body of the method a change touched" do
      expect(described_class.mask(source, nil, source.sub(":large\n", ":larger\n"))).to eq(0b11111 << 4)
    end

    it "masks a method written on one line by its own line" do
      expect(described_class.mask(source, nil, source.sub("= :small", "= :smaller"))).to eq(0b10)
    end

    it "masks the innermost method a change touched" do
      expect(described_class.mask(source, nil, source.sub(":inner", ":innermost"))).to eq(0b11 << 5)
    end

    it "masks a method changed in two places once" do
      changed = source.sub("def large", "def large(size = 1)").sub(":large\n", ":larger\n")

      expect(described_class.mask(source, nil, changed)).to eq(0b11111 << 4)
    end

    it "masks the inner of two methods ending on one line" do
      nested = "class Widget\n  def outer\n    def inner\n      :inner\n    end end\nend\n"

      expect(described_class.mask(nested, nil, nested.sub(":inner", ":innermost"))).to eq(0b11 << 3)
    end

    it "combines the methods of every change" do
      changed = source.sub("= :small", "= :smaller").sub(":inner", ":innermost")

      expect(described_class.mask(source, nil, changed)).to eq(0b1100010)
    end

    it "masks the changes between the base and the recording too" do
      expect(described_class.mask(source, source.sub(":large\n", ":larger\n"), source)).to eq(0b11111 << 4)
    end

    it "reads the changes between the base and the recording in the recording's lines" do
      base = source.sub("    :large\n", "    :large\n#{"    :gone\n" * 6}")

      expect(described_class.mask(source, base, source)).to eq(0b11111 << 4)
    end

    it "masks nothing for no change at all" do
      expect(described_class.mask(source, source, source)).to eq(0)
    end

    it "gives up on a change outside every method" do
      expect(described_class.mask(source, nil, source.sub("class Widget", "class Gadget"))).to be_nil
    end

    it "gives up on a method added between two" do
      expect(described_class.mask(source, nil, source.sub("\n  def large", "\n  def medium = 1\n\n  def large"))).to be_nil
    end

    it "gives up without Prism" do
      allow(described_class).to receive(:prism?).and_return(false)

      expect(described_class.mask(source, nil, source.sub(":large\n", ":larger\n"))).to be_nil
    end
  end

  describe ".changed_spots" do
    it "reads a replaced line on both sides" do
      expect(described_class.changed_spots(source, source.sub(":large\n", ":larger\n"))).to eq([[[8, 8], [8, 8]]])
    end

    it "reads an insertion as the lines around it, on the side it leaves untouched" do
      expect(described_class.changed_spots(source, source.sub("    :large\n", "    :large\n    :again\n")))
        .to eq([[[8, 9], [9, 9]]])
    end

    it "reads several lines" do
      expect(described_class.changed_spots(source, source.sub("class Widget\n", "class Widget\n  A = 1\n  B = 2\n")))
        .to eq([[[1, 2], [2, 3]]])
    end

    it "finds nothing without an old side" do
      expect(described_class.changed_spots(nil, source)).to eq([])
    end
  end

  describe ".innermost" do
    let(:methods) { [[4, 9], [5, 7]] }

    it "picks the smallest method around a spot" do
      expect(described_class.innermost(methods, [6, 6])).to eq([5, 7])
    end

    it "finds no method around a spot reaching past them all" do
      expect(described_class.innermost(methods, [9, 10])).to be_nil
    end
  end

  describe ".body_mask" do
    it "covers the lines after the def line" do
      expect(described_class.body_mask(2, 4)).to eq(0b1100)
    end

    it "covers the def line of a one-line method" do
      expect(described_class.body_mask(3, 3)).to eq(0b100)
    end
  end
end
