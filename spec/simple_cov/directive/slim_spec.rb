# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Directive::Slim do
  describe ".ruby_lines" do
    it "blanks text and tag lines and keeps the line count" do
      expect(described_class.ruby_lines(["h1 Title\n", "  | text\n", "  ' text\n", "#main\n"])).to eq(["        \n", "        \n", "        \n", "     \n"])
    end

    it "keeps a control line's Ruby at its own column" do
      expect(described_class.ruby_lines(["  - if @admin\n"])).to eq(["    if @admin\n"])
    end

    it "keeps an output line's Ruby, whatever its marker" do
      expect(described_class.ruby_lines(["= @foo.bar\n", "== raw\n", "=' spaced\n"])).to eq(["  @foo.bar\n", "   raw\n", "   spaced\n"])
    end

    it "keeps the Ruby a tag outputs" do
      expect(described_class.ruby_lines(["h1 = @foo.bar\n", "li.x#y== item\n"])).to eq(["     @foo.bar\n", "         item\n"])
    end

    it "treats a tag with attributes as text" do
      expect(described_class.ruby_lines(["a href=url = text\n"])).to eq(["                 \n"])
    end

    it "turns a Slim comment into a Ruby comment" do
      expect(described_class.ruby_lines(["/ simplecov:disable\n", "/! html comment\n"])).to eq(["# simplecov:disable\n", "#! html comment\n"])
    end

    it "keeps an indented Slim comment at its own column" do
      expect(described_class.ruby_lines(["  / simplecov:disable\n"])).to eq(["  # simplecov:disable\n"])
    end

    it "continues an indented Slim comment on every line under it" do
      lines = ["/\n", "  simplecov:disable\n", "p\n"]

      expect(described_class.ruby_lines(lines)).to eq(["#\n", "# simplecov:disable\n", " \n"])
    end

    it "keeps a blank line inside a Slim comment without ending it" do
      lines = ["/\n", "\n", "  simplecov:disable\n"]

      expect(described_class.ruby_lines(lines)).to eq(["#\n", "\n", "# simplecov:disable\n"])
    end

    it "keeps the lines of an embedded ruby block" do
      lines = ["  ruby:\n", "    # simplecov:disable\n", "    x = 1\n", "  p\n"]

      expect(described_class.ruby_lines(lines)).to eq(["       \n", "    # simplecov:disable\n", "    x = 1\n", "   \n"])
    end

    it "blanks the lines of any other embedded block, even ones shaped like code" do
      lines = ["  markdown:\n", "    - # simplecov:disable\n"]

      expect(described_class.ruby_lines(lines)).to eq(["           \n", "                         \n"])
    end

    it "treats a nested inline tag as text rather than an embedded block" do
      expect(described_class.ruby_lines(["p: span\n", "  = foo\n"])).to eq(["       \n", "    foo\n"])
    end

    it "terminates lines that arrive without one, so the line numbers stay put" do
      expect(described_class.ruby_lines(["- a", "- b"])).to eq(["  a\n", "  b\n"])
    end

    it "answers the lines untouched when they cannot be scanned" do
      utf16 = ["/ simplecov:disable".encode("UTF-16LE")]

      expect(described_class.ruby_lines(utf16)).to equal(utf16)
    end
  end

  describe "through SimpleCov::Directive.disabled_ranges" do
    def ranges_for(template)
      SimpleCov::Directive.disabled_ranges(described_class.ruby_lines(template.lines))
    end

    let(:slim_comments) do
      <<~SLIM
        h1 = @foo.bar
        / simplecov:disable
        - if @admin
          p Only an admin sees this.
        / simplecov:enable
        p = @footer
      SLIM
    end

    let(:ruby_comments) do
      <<~SLIM
        h1 = @foo.bar
        - # simplecov:disable line
        - if @admin
          p Only an admin sees this.
        - # simplecov:enable line
        p = @footer
      SLIM
    end

    it "finds a block directive written as Slim comments" do
      expect(ranges_for(slim_comments)).to eq(line: [2..5], branch: [2..5], method: [2..5])
    end

    it "finds a block directive written as Ruby comments on control lines" do
      expect(ranges_for(ruby_comments)).to eq(line: [2..5], branch: [], method: [])
    end

    it "treats a directive trailing an output line as inline" do
      expect(ranges_for(%(h1 = @foo.bar\n= raise "absurd" # simplecov:disable\n))).to eq(line: [2..2], branch: [2..2], method: [2..2])
    end

    it "treats a directive trailing a tag's output as inline" do
      expect(ranges_for(%(h1 = @foo.bar\np = raise "absurd" # simplecov:disable\n))).to eq(line: [2..2], branch: [2..2], method: [2..2])
    end

    it "ignores a directive marker inside a string" do
      expect(ranges_for(%(= "# simplecov:disable"\np = @footer\n))).to eq(line: [], branch: [], method: [])
    end
  end
end
