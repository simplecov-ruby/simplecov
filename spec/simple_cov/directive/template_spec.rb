# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Directive::Template do
  describe ".template?" do
    it "answers yes for the template languages it reads" do
      expect(%w[show.html.erb show.html.haml show.html.slim].map { |name| described_class.template?(name) }).to all(be true)
    end

    it "answers no for a Ruby file" do
      expect(described_class.template?("foo.rb")).to be false
    end
  end

  describe ".ruby_lines" do
    it "reads an ERB template's tags" do
      expect(described_class.ruby_lines("show.html.erb", ["<p><%= foo %></p>\n"])).to eq(["       foo ;     \n"])
    end

    it "reads a Haml template's script lines" do
      expect(described_class.ruby_lines("show.html.haml", ["%p= foo\n"])).to eq(["    foo\n"])
    end

    it "reads a Slim template's output lines" do
      expect(described_class.ruby_lines("show.html.slim", ["p = foo\n"])).to eq(["    foo\n"])
    end

    it "answers a Ruby file's lines untouched" do
      lines = ["foo\n"]

      expect(described_class.ruby_lines("foo.rb", lines)).to equal(lines)
    end
  end
end
