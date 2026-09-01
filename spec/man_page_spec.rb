# frozen_string_literal: true

require "helper"
require_relative "../tasks/man_page"

RSpec.describe ManPage do
  let(:page) { described_class.build }

  it "matches the committed man/simplecov.1 (regenerate with `rake man`)" do
    expect(File.read(File.expand_path("../man/simplecov.1", __dir__))).to eq(page)
  end

  it "opens with the roff title macro" do
    expect(page).to start_with(".TH SIMPLECOV 1")
  end

  it "renders every command" do
    expect(page).to include(*SimpleCov::CLI::COMMANDS.keys.map { |command| "\n.B #{described_class.escape(command)}" })
  end

  it "escapes the dashes in an option name" do
    expect(page).to include(".B \\-\\-criterion C")
  end

  it "documents the badge command's own text" do
    expect(page).to include("badge")
  end

  it "leaves the suite's own dogfood paths out" do
    expect(page).not_to include("tmp/dogfood")
  end

  it "guards wrapped lines that would begin with a roff control character" do
    expect(described_class.guard_control(".simplecov would be a macro here")).to start_with("\\&.")
  end
end
