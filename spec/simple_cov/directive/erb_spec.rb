# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Directive::Erb do
  describe ".ruby_lines" do
    it "blanks the text outside the tags and keeps the line count" do
      expect(described_class.ruby_lines(["<p>\n", "  Hello\n", "</p>\n"])).to eq(["   \n", "       \n", "    \n"])
    end

    it "keeps a tag's Ruby at its own column, closing it with a semicolon" do
      expect(described_class.ruby_lines(["<p><%= foo %></p>\n"])).to eq(["       foo ;     \n"])
    end

    it "keeps the Ruby of a tag that spans lines" do
      lines = ["<%-\n", "  if foo\n", "-%>\n"]

      expect(described_class.ruby_lines(lines)).to eq(["   \n", "  if foo\n", ";  \n"])
    end

    it "turns a comment tag into a Ruby comment" do
      expect(described_class.ruby_lines(["<%# simplecov:disable %>\n"])).to eq(["  # simplecov:disable   \n"])
    end

    it "continues a comment tag that spans lines on every line" do
      lines = ["<%#\n", "  simplecov:disable\n", "%>\n"]

      expect(described_class.ruby_lines(lines)).to eq(["  #\n", "#  simplecov:disable\n", "#  \n"])
    end

    it "treats an escaped tag opener as text" do
      expect(described_class.ruby_lines(["<%% foo %>\n"])).to eq(["          \n"])
    end

    it "treats an unclosed tag as text" do
      expect(described_class.ruby_lines(["<% foo\n", "bar\n"])).to eq(["      \n", "   \n"])
    end

    it "terminates lines that arrive without one, so the line numbers stay put" do
      expect(described_class.ruby_lines(["<% a %>", "<% b %>"])).to eq(["   a ; \n", "   b ; \n"])
    end

    it "answers the lines untouched when they cannot be scanned" do
      utf16 = ["<%# simplecov:disable %>".encode("UTF-16LE")]

      expect(described_class.ruby_lines(utf16)).to equal(utf16)
    end
  end

  describe "through SimpleCov::Directive.disabled_ranges" do
    def ranges_for(template)
      SimpleCov::Directive.disabled_ranges(described_class.ruby_lines(template.lines))
    end

    let(:ruby_comments_in_code_tags) do
      <<~ERB
        <%- if controller_name != 'sessions' %>
          <p><%= link_to "Log in", new_session_path(resource_name) %></p>
        <% end %>
        <%-
          # simplecov:disable
          if devise_mapping.confirmable? && controller_name != 'confirmations'
        %>
          <p><%= link_to "Didn't receive confirmation instructions?", new_confirmation_path(resource_name) %></p>
        <%
          end
          # simplecov:enable
        %>
        <p><%= @footer %></p>
      ERB
    end

    let(:comment_tags) do
      <<~ERB
        <p><%= @header %></p>
        <%# simplecov:disable line %>
        <% if @admin %>
          <p>Only an admin sees this.</p>
        <% end %>
        <%# simplecov:enable line %>
      ERB
    end

    let(:trailing_comment_tag) do
      <<~ERB
        <p><%= @header %></p>
        <%= raise "absurd" %> <%# simplecov:disable %>
        <p><%= @footer %></p>
      ERB
    end

    it "finds a block directive written as Ruby comments inside a code tag" do
      expect(ranges_for(ruby_comments_in_code_tags)).to eq(line: [5..11], branch: [5..11], method: [5..11])
    end

    it "finds a block directive written as an ERB comment tag" do
      expect(ranges_for(comment_tags)).to eq(line: [2..6], branch: [], method: [])
    end

    it "treats an ERB comment tag trailing a code tag as inline" do
      expect(ranges_for(trailing_comment_tag)).to eq(line: [2..2], branch: [2..2], method: [2..2])
    end

    it "ignores a directive marker inside a string in a tag" do
      expect(ranges_for(%(<%= "# simplecov:disable" %>\n<%= @footer %>\n))).to eq(line: [], branch: [], method: [])
    end
  end
end
