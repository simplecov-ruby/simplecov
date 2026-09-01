# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Directive do
  describe ".disabled_ranges" do
    let(:empty_ranges) { {line: [], branch: [], method: []} }

    it "returns empty ranges per category for source without directives" do
      expect(described_class.disabled_ranges(["def foo", "  bar", "end"])).to eq empty_ranges
    end

    it "treats a bare disable/enable as targeting all categories" do
      ranges = described_class.disabled_ranges([
        "# simplecov:disable", # 1
        "code",                # 2
        "# simplecov:enable"   # 3
      ])

      expect(ranges[:line]).to eq [1..3]
      expect(ranges[:branch]).to eq [1..3]
      expect(ranges[:method]).to eq [1..3]
    end

    it "builds ranges between matching block disable/enable for the named category" do
      ranges = described_class.disabled_ranges([
        "def foo", # 1
        "  # simplecov:disable line", # 2
        "  bar",                      # 3
        "  baz",                      # 4
        "  # simplecov:enable line",  # 5
        "end"                         # 6
      ])

      expect(ranges).to eq(line: [2..5], branch: [], method: [])
    end

    it "extends an unclosed disable to the end of file" do
      ranges = described_class.disabled_ranges([
        "x = 1", # 1
        "# simplecov:disable", # 2
        "y = 2",               # 3
        "z = 3"                # 4
      ])

      expect(ranges).to eq(line: [2..4], branch: [2..4], method: [2..4])
    end

    it "treats inline disable as a single-line range" do
      ranges = described_class.disabled_ranges([
        "x = 1", # 1
        'raise "absurd" # simplecov:disable', # 2
        "y = 2"                               # 3
      ])

      expect(ranges).to eq(line: [2..2], branch: [2..2], method: [2..2])
    end

    it "treats an inline simplecov:enable as a no-op (not a single-line disable)" do
      ranges = described_class.disabled_ranges([
        'raise "absurd" # simplecov:enable line', # 1
        "y = 2"                                   # 2
      ])

      expect(ranges[:line]).to eq []
    end

    it "tracks each category independently" do
      ranges = described_class.disabled_ranges([
        "# simplecov:disable line", # 1
        "# simplecov:disable branch,method", # 2
        "code",                             # 3
        "# simplecov:enable line",          # 4
        "code",                             # 5
        "# simplecov:enable branch"         # 6
      ])

      expect(ranges[:line]).to eq [1..4]
      expect(ranges[:branch]).to eq [2..6]
      expect(ranges[:method]).to eq [2..6]
    end

    it "ignores enable without a matching disable" do
      ranges = described_class.disabled_ranges([
        "code", # 1
        "# simplecov:enable line", # 2
        "more code"                # 3
      ])

      expect(ranges[:line]).to eq []
    end

    it "supports multiple disable/enable pairs in the same file" do
      ranges = described_class.disabled_ranges([
        "# simplecov:disable line", # 1
        "a",                        # 2
        "# simplecov:enable line",  # 3
        "b",                        # 4
        "# simplecov:disable line", # 5
        "c",                        # 6
        "# simplecov:enable line"   # 7
      ])

      expect(ranges[:line]).to eq [1..3, 5..7]
    end

    it "tolerates whitespace around the marker, colon, and category separators" do
      ranges = described_class.disabled_ranges([
        "#simplecov:disable line", # 1
        "code",                                      # 2
        "  #  simplecov : enable line",              # 3
        "code",                                      # 4
        "# simplecov:disable method ,  branch",      # 5
        "code",                                      # 6
        "# simplecov:enable method, branch"          # 7
      ])

      expect(ranges[:line]).to eq [1..3]
      expect(ranges[:branch]).to eq [5..7]
      expect(ranges[:method]).to eq [5..7]
    end

    describe "free-form trailing reason" do
      it "accepts an unstructured reason after a block disable" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable line legacy adapter, scheduled for removal", # 1
          "code",                                                           # 2
          "# simplecov:enable line"                                         # 3
        ])

        expect(ranges[:line]).to eq [1..3]
      end

      it "accepts a `--`-prefixed reason for users who like the visual separator" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable line -- legacy adapter, scheduled for removal",
          "code",
          "# simplecov:enable line"
        ])

        expect(ranges[:line]).to eq [1..3]
      end

      it "accepts a reason on a bare directive" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable not interesting", # 1
          "code" # 2
        ])

        expect(ranges[:line]).to eq [1..2]
      end

      it "accepts a reason on an inline directive" do
        ranges = described_class.disabled_ranges([
          'raise "absurd" # simplecov:disable line impossible', # 1
          "ok" # 2
        ])

        expect(ranges[:line]).to eq [1..1]
      end
    end

    describe "lenient handling of unrecognised category text" do
      it "treats an unknown single token as a reason on the bare form (over-disables)" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable cyclomatic", # 1
          "code"                            # 2
        ])

        expect(ranges).to eq(line: [1..2], branch: [1..2], method: [1..2])
      end

      it "treats a reason that merely starts with a category name as the bare form" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable linear algebra reasons", # 1
          "code"                                        # 2
        ])

        expect(ranges).to eq(line: [1..2], branch: [1..2], method: [1..2])
      end

      it "stops parsing categories at the first unrecognised entry, treats the rest as reason" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable line, frobnicate", # 1
          "code"                                  # 2
        ])

        expect(ranges[:line]).to eq [1..2]
        expect(ranges[:branch]).to eq []
        expect(ranges[:method]).to eq []
      end

      it "accepts `all` as syntactic sugar for the bare form" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable all", # 1
          "code"                     # 2
        ])

        expect(ranges).to eq(line: [1..2], branch: [1..2], method: [1..2])
      end

      it "discards trailing punctuation as reason text" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable line; please", # 1
          "code"                              # 2
        ])

        expect(ranges[:line]).to eq [1..2]
      end

      it "tolerates a trailing comma in the category list" do
        ranges = described_class.disabled_ranges([
          "# simplecov:disable line,", # 1
          "code"                       # 2
        ])

        expect(ranges[:line]).to eq [1..2]
      end
    end

    describe "still-rejected inputs" do
      it "ignores an unknown mode" do
        ranges = described_class.disabled_ranges([
          "# simplecov:silence line", # 1
          "code"                      # 2
        ])

        expect(ranges).to eq(line: [], branch: [], method: [])
      end

      it "ignores lines containing invalid byte sequences" do
        bad = +"# simplecov:disable line"
        bad << 0xC3.chr.force_encoding("UTF-8")

        expect(described_class.disabled_ranges([bad, "code"])).to eq empty_ranges
      end
    end

    describe "string- and heredoc-safety" do
      it "ignores a directive marker that appears inside a double-quoted string" do
        ranges = described_class.disabled_ranges([
          'BANNER = "# simplecov:disable line"', # 1
          "puts BANNER" # 2
        ])

        expect(ranges).to eq empty_ranges
      end

      it "ignores a directive marker that appears inside a single-quoted string" do
        ranges = described_class.disabled_ranges([
          "BANNER = '# simplecov:disable line'", # 1
          "puts BANNER" # 2
        ])

        expect(ranges).to eq empty_ranges
      end

      it "ignores a directive marker that appears inside a heredoc" do
        ranges = described_class.disabled_ranges([
          "msg = <<~TEXT", # 1
          "  # simplecov:disable line", # 2
          "  body",                     # 3
          "  # simplecov:enable line",  # 4
          "TEXT",                       # 5
          "puts msg"                    # 6
        ])

        expect(ranges).to eq empty_ranges
      end

      it "ignores a directive marker inside an interpolated string" do
        ranges = described_class.disabled_ranges([
          'name = "x"', # 1
          'puts "name=#{name} # simplecov:disable line"', # rubocop:disable Lint/InterpolationCheck
          "ok" # 3
        ])

        expect(ranges).to eq empty_ranges
      end

      it "still recognises a real directive on the same file as a string-shaped marker" do
        ranges = described_class.disabled_ranges([
          'BANNER = "# simplecov:disable"', # 1
          "# simplecov:disable line",        # 2
          "skipped",                         # 3
          "# simplecov:enable line"          # 4
        ])

        expect(ranges[:line]).to eq [2..4]
      end
    end

    describe "inline detection edge cases" do
      it "treats indented own-line directives as block, not inline" do
        ranges = described_class.disabled_ranges([
          "    # simplecov:disable line", # 1
          "    code",                     # 2
          "    # simplecov:enable line"   # 3
        ])

        expect(ranges[:line]).to eq [1..3]
      end

      it "treats a directive that follows another `#` segment as inline" do
        ranges = described_class.disabled_ranges([
          "# prefix # simplecov:disable line", # 1
          "still relevant" # 2
        ])

        expect(ranges[:line]).to eq [1..1]
      end
    end

    it "tokenizes nothing when no line so much as mentions the gem" do
      allow(Ripper).to receive(:lex).and_call_original

      expect(described_class.disabled_ranges(["def foo", "  bar", "end"])).to eq empty_ranges
      expect(Ripper).not_to have_received(:lex)
    end
  end

  describe "the parsing steps" do
    it "answers whether any line so much as mentions the gem" do
      expect(described_class.send(:source_might_contain_directive?, ["def foo", "  bar", "end"])).to be false
      expect(described_class.send(:source_might_contain_directive?, ["  # simplecov:disable line"])).to be true
      expect(described_class.send(:source_might_contain_directive?, [])).to be false
    end

    it "answers no for a line whose encoding cannot be searched" do
      utf16 = "# simplecov:disable line".encode("UTF-16LE")

      expect(described_class.send(:source_might_contain_directive?, [utf16])).to be false
    end

    it "reports each comment with the line and column it starts at" do
      lines = ["x = 1 # first\n", "# second\n"]

      expect(described_class.send(:comments_in, lines)).to eq([[1, 6, "# first\n"], [2, 0, "# second\n"]])
    end

    it "terminates lines that arrive without one, so the line numbers stay put" do
      expect(described_class.send(:comments_in, ["x = 1", "# c"])).to eq([[2, 0, "# c\n"]])
    end

    it "finds no comments in source it cannot tokenize" do
      utf16 = "# simplecov:disable line".encode("UTF-16LE")

      expect(described_class.send(:comments_in, [utf16])).to eq([])
    end

    it "reads a comment into a directive" do
      directive = described_class.send(:parse_comment, ["# simplecov:disable line"], 1, 0, "# simplecov:disable line")

      expect(directive.line_number).to eq(1)
      expect(directive.mode).to eq(:disable)
      expect(directive.categories).to eq(%i[line])
      expect(directive.inline?).to be false
    end

    it "reads the other mode, and the bare form's categories, the same way" do
      directive = described_class.send(:parse_comment, ["code # simplecov:enable"], 1, 5, "# simplecov:enable")

      expect(directive.mode).to eq(:enable)
      expect(directive.categories).to eq(%i[line branch method])
      expect(directive.inline?).to be true
    end

    it "reads no directive out of a comment that is not one, or one it cannot match" do
      invalid = (+"# simplecov:disable line\xC3").force_encoding("UTF-8")

      expect(described_class.send(:parse_comment, ["# nope"], 1, 0, "# nope")).to be_nil
      expect(described_class.send(:parse_comment, [invalid], 1, 0, invalid)).to be_nil
    end

    it "names the categories a directive lists, and every one when it lists none" do
      expect(described_class.send(:parse_categories, nil)).to eq(%i[line branch method])
      expect(described_class.send(:parse_categories, "branch , method")).to eq(%i[branch method])
    end

    it "answers whether anything but indentation precedes the directive's column" do
      expect(described_class.send(:inline?, ["prefix", "  # x", "tail!"], 2, 2)).to be false
      expect(described_class.send(:inline?, ["code # x", "     "], 1, 5)).to be true
      expect(described_class.send(:inline?, ["# x"], 1, 0)).to be false
    end

    it "answers not inline for a line the array does not have" do
      expect(described_class.send(:inline?, [], 1, 0)).to be false
    end

    it "answers not inline for a column nothing can be sliced at" do
      expect(described_class.send(:inline?, ["code # x"], 1, -1)).to be false
    end

    it "answers not inline for a prefix whose bytes are invalid" do
      invalid = (+"\xC3 = 1 # simplecov:disable").force_encoding("UTF-8")

      expect(described_class.send(:inline?, [invalid], 1, 7)).to be false
    end
  end
end
