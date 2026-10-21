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

  def mask(...) = described_class.changes(...).first

  def load_time(...) = described_class.changes(...).last.map(&:first)

  def named(...) = described_class.changes(...).last.map(&:last)

  describe ".changes" do
    it "masks the body of the method a change touched" do
      expect(mask(source, nil, source.sub(":large\n", ":larger\n"))).to eq(0b11111 << 4)
    end

    it "masks a method written on one line by its own line" do
      expect(mask(source, nil, source.sub("= :small", "= :smaller"))).to eq(0b10)
    end

    it "masks the innermost method a change touched" do
      expect(mask(source, nil, source.sub(":inner", ":innermost"))).to eq(0b11 << 5)
    end

    it "masks a method changed in two places once" do
      changed = source.sub("def large", "def large(size = 1)").sub(":large\n", ":larger\n")

      expect(mask(source, nil, changed)).to eq(0b11111 << 4)
    end

    it "masks the inner of two methods ending on one line" do
      nested = "class Widget\n  def outer\n    def inner\n      :inner\n    end end\nend\n"

      expect(mask(nested, nil, nested.sub(":inner", ":innermost"))).to eq(0b11 << 3)
    end

    it "combines the methods of every change" do
      changed = source.sub("= :small", "= :smaller").sub(":inner", ":innermost")

      expect(mask(source, nil, changed)).to eq(0b1100010)
    end

    it "masks the changes between the base and the recording too" do
      expect(mask(source, source.sub(":large\n", ":larger\n"), source)).to eq(0b11111 << 4)
    end

    it "reads the changes between the base and the recording in the recording's lines" do
      base = source.sub("    :large\n", "    :large\n#{"    :gone\n" * 6}")

      expect(mask(source, base, source)).to eq(0b11111 << 4)
    end

    it "masks nothing for no change at all" do
      expect(mask(source, source, source)).to eq(0)
    end

    it "gives up on a change outside every method" do
      expect(mask(source, nil, source.sub("class Widget", "class Gadget"))).to be_nil
    end

    it "gives up on a method added between two" do
      expect(mask(source, nil, source.sub("\n  def large", "\n  def medium = 1\n\n  def large"))).to be_nil
    end

    it "gives up without Prism" do
      allow(described_class).to receive(:prism?).and_return(false)

      expect(mask(source, nil, source.sub(":large\n", ":larger\n"))).to be_nil
    end
  end

  describe "load-time lines" do
    let(:constant) { source.sub("class Widget\n", "class Widget\n  LIMIT = [\n    1, # one\n  ].freeze\n  # The sizes.\n") }

    it "reads a rewritten statement outside every method by its first line" do
      expect(load_time(constant, nil, constant.sub("1, #", "2, #"))).to eq([2])
    end

    it "reads a statement once however many of its lines changed" do
      expect(load_time(constant, nil, constant.sub("[\n    1,", "[\n    2,").sub("].freeze", "]"))).to eq([2])
    end

    it "reads the statement around an inner one" do
      expect(load_time(source, nil, source.sub("class Widget", "class Gadget"))).to eq([1])
    end

    it "reads a code line whose comment changed" do
      expect(load_time(constant, nil, constant.sub("# one", "# uno"))).to eq([2])
    end

    it "leaves out a rewritten comment line" do
      expect(load_time(constant, nil, constant.sub("# The sizes.", "# The widths."))).to eq([])
    end

    it "leaves out a line no statement holds" do
      block_comment = "=begin\nA note.\n=end\n#{source}"

      expect(load_time(block_comment, nil, block_comment.sub("A note.", "A longer note."))).to eq([])
    end

    it "leaves out a rewritten line inside a block comment between statements" do
      block_comment = source.sub("\n\n", "\n=begin\nA note.\n=end\n\n")

      expect(load_time(block_comment, nil, block_comment.sub("A note.", "A longer note."))).to eq([])
    end

    it "leaves out a block comment rewritten along with its =begin line" do
      block_comment = source.sub("\n\n", "\n=begin\nA note.\n=end\n\n")

      expect(load_time(block_comment, nil, block_comment.sub("=begin\nA note.", "=begin notes\nA longer note."))).to eq([])
    end

    it "names a rewritten line by its own line in the working tree" do
      expect(named(constant, nil, constant.sub("1, #", "2, #"))).to eq([3])
    end

    it "names an addition by its first line of code in the working tree" do
      expect(named(source, nil, source.sub("\n\n", "\n  # Other.\n  OTHER = 5\n\n"))).to eq([4])
    end

    it "names a change between the base and the recording in the recording's lines" do
      expect(named(source, source.sub("class Widget", "class Gadget"), source)).to eq([1])
    end

    it "names each statement a hunk rewrote by its own line" do
      pair = source.sub("class Widget\n", "class Widget\n  A = 1\n  B = 2\n")

      expect(named(pair, nil, pair.sub("A = 1\n  B = 2", "A = 3\n  B = 4"))).to eq([2, 3])
    end

    it "names a statement past the end of a shorter hunk by the hunk's last line" do
      pair = source.sub("class Widget\n", "class Widget\n  A = 1\n  B = 2\n")

      expect(named(pair, nil, pair.sub("  A = 1\n  B = 2\n", "  A = 3\n"))).to eq([2, 2])
    end

    it "names a deleted statement by the line after it" do
      constant = source.sub("class Widget\n", "class Widget\n  OTHER = 5\n")

      expect(named(constant, nil, source)).to eq([2])
    end

    it "names a deletion between the base and the recording by the line after it" do
      expect(named(source, source.sub("\n\n", "\n  OTHER = 5\n\n"), source)).to eq([3])
    end

    it "names a statement the recording blanked by the blank line" do
      blanked = source.sub("\n\n", "\n\n\n")

      expect(named(blanked, blanked.sub("\n\n\n", "\n  OTHER = 5\n\n"), blanked)).to eq([3])
    end

    it "reads a rewritten heredoc body at the top of the file by the statement that opens it" do
      text = "TEXT = <<~T\n  hello\nT\n#{source}"

      expect(load_time(text, nil, text.sub("hello", "goodbye"))).to eq([1])
    end

    it "reads a rewritten heredoc body in a class by the statement that opens it, not the class" do
      text = source.sub("class Widget\n", "class Widget\n  TEXT = <<~T\n    hello\n  T\n")

      expect(load_time(text, nil, text.sub("hello", "goodbye"))).to eq([2])
    end

    it "reads a statement through the last of the heredocs it opens" do
      text = "PAIR = [<<~A, <<~B]\n  a\nA\n  b\nB\n#{source}"

      expect(load_time(text, nil, text.sub("  b\n", "  c\n"))).to eq([1])
    end

    it "reads interpolated and command heredocs by the statements that open them" do
      text = "A = <<~T\n  \#{1}\n  apple\nT\nB = <<~`T`\n  echo banana\nT\nC = <<~`T`\n  echo \#{2}\n  cherry\nT\n#{source}"
      changed = text.sub("apple", "apricot").sub("banana", "blueberry").sub("cherry", "currant")

      expect(load_time(text, nil, changed)).to eq([1, 5, 8])
    end

    it "reads a rewritten interpolated heredoc terminator by the statement that opens it" do
      text = "A = <<~ATEXT\n  \#{1}\n  ATEXT\nC = <<~`CTEXT`\n  echo \#{2}\n  CTEXT\n#{source}"
      changed = text.sub("  ATEXT\n", "ATEXT\n").sub("  CTEXT\n", "CTEXT\n")

      expect(load_time(text, nil, changed)).to eq([1, 4])
    end

    it "reads a statement whose strings have no terminator" do
      text = "CHAR = ?a\nPAIR = \"a\" \"b\"\n#{source}"

      expect(load_time(text, nil, text.sub("?a", "?b").sub('"b"', '"c"'))).to eq([1, 2])
    end

    it "leaves out a rewritten line after __END__" do
      data = "#{source}__END__\nsome data\n"

      expect(load_time(data, nil, data.sub("some data", "other data"))).to eq([])
    end

    it "names a statement once, by its first changed line" do
      expect(named(constant, nil, constant.sub("[\n    1,", "[\n    2,").sub("].freeze", "]"))).to eq([3])
    end

    it "reads a statement turned into a comment" do
      constant = source.sub("class Widget\n", "class Widget\n  OTHER = 5\n")

      expect(load_time(constant, nil, constant.sub("OTHER", "# OTHER"))).to eq([2])
    end

    it "reads comments on the first and last lines rewritten into statements like additions" do
      framed = "# A widget.\n#{source}# The end.\n"
      changes = [framed.sub("# A widget.", "FIRST = 5"), framed.sub("# The end.", "LAST = 5")]

      expect(changes.map { |changed| load_time(framed, nil, changed) }).to eq([[2], [2]])
    end

    it "leaves out a changed def line, which the mask covers" do
      expect(load_time(source, nil, source.sub("def large", "def large(size = 1)"))).to eq([])
    end

    it "leaves out a changed method written on one line" do
      expect(load_time(source, nil, source.sub("= :small", "= :smaller"))).to eq([])
    end

    it "leaves out a changed def line inside another statement" do
      prefixed = source.sub("  def large", "  private \\\n  def large")

      expect(load_time(prefixed, nil, prefixed.sub("def large", "def large(size = 1)"))).to eq([])
    end

    it "reads a changed line in a method body by its statement" do
      expect(load_time(source, nil, source.sub(":inner", ":innermost"))).to eq([6])
    end

    it "reads an addition outside every method by the statement around it" do
      expect(load_time(source, nil, source.sub("\n\n", "\n  OTHER = 5\n\n"))).to eq([1])
    end

    it "reads an addition by the statement around it, not the file's first" do
      required = "require \"set\"\n#{source}"

      expect(load_time(required, nil, required.sub("\n\n", "\n  OTHER = 5\n\n"))).to eq([2])
    end

    it "reads a blank line rewritten into a statement like an addition" do
      expect(load_time(source, nil, source.sub("\n\n", "\n  OTHER = 5\n"))).to eq([1])
    end

    it "reads an addition at the top of the file by its first statement" do
      expect(load_time(source, nil, "OTHER = 5\n#{source}")).to eq([1])
    end

    it "reads a deletion between the base and the recording in the recording's lines" do
      expect(load_time(source, source.sub("\n\n", "\n  OTHER = 5\n\n"), source)).to eq([1])
    end

    it "leaves out an added method" do
      expect(load_time(source, nil, source.sub("\n\n", "\n\n  def medium = 1\n\n"))).to eq([])
    end

    it "reads an addition with a statement after a method" do
      expect(load_time(source, nil, source.sub("\n\n", "\n\n  def medium = 1\n  OTHER = 5\n\n"))).to eq([1])
    end

    it "leaves out a blank line rewritten into a method" do
      expect(load_time(source, nil, source.sub("\n\n", "\n  def medium = 1\n"))).to eq([])
    end

    it "leaves out an added comment" do
      expect(load_time(source, nil, source.sub("\n\n", "\n  # Sizes.\n\n"))).to eq([])
    end

    it "leaves out an addition inside a method" do
      expect(load_time(source, nil, source.sub("    :large\n", "    :large\n    OTHER = 5\n"))).to eq([])
    end

    it "reads nothing from an addition to an empty file" do
      expect(load_time("", nil, "OTHER = 5\n")).to eq([])
    end

    it "reads every rewritten line without Prism" do
      allow(described_class).to receive(:prism?).and_return(false)

      expect(described_class.changes(source, nil, source.sub(":large\n", ":larger\n  :again\n"))).to eq([nil, [[8, 8]]])
    end
  end

  describe ".enclosed_lines" do
    it "finds the lines between a =begin and its =end" do
      comments = Prism.parse("A = 1 # one\n=begin\nx\ny\n=end\nB = 2\n").comments

      expect(described_class.enclosed_lines(comments)).to eq([3, 4])
    end
  end

  describe ".hunks" do
    it "reads each hunk's first line, line count, and text on both sides" do
      expect(described_class.hunks("a\nb\nc\n", "a\nx\ny\nb\nd\n"))
        .to eq([[[1, 0, ""], [2, 2, "x\ny\n"]], [[3, 1, "c\n"], [5, 1, "d\n"]]])
    end

    it "finds nothing without an old side" do
      expect(described_class.hunks(nil, source)).to eq([])
    end
  end

  describe ".spot" do
    it "covers the lines a side rewrote" do
      expect([[8, 1, ""], [1, 2, ""]].map { |side| described_class.spot(side) }).to eq([[8, 8], [1, 2]])
    end

    it "covers the two lines around an insertion" do
      expect(described_class.spot([8, 0, ""])).to eq([8, 9])
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
