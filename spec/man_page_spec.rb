# frozen_string_literal: true

require "helper"
require_relative "../tasks/man_page"

# The committed man page is a build artifact of the usage document,
# like the compiled HTML template is of the frontend. This gate keeps
# it current: any change to the usage text (or the version) that isn't
# followed by `rake man` fails here.
RSpec.describe ManPage do
  it "matches the committed man/simplecov.1 (regenerate with `rake man`)" do
    committed = File.read(File.expand_path("../man/simplecov.1", __dir__))
    expect(committed).to eq(described_class.build)
  end

  it "renders every command with roff-safe text" do
    page = described_class.build
    expect(page).to start_with(".TH SIMPLECOV 1")
    SimpleCov::CLI::COMMANDS.each_key do |command|
      expect(page).to include("\n.B #{command}")
    end
    expect(page).to include(".B \\-\\-criterion C").and include("badge")
    expect(page).not_to include("tmp/dogfood")
  end

  it "guards wrapped lines that would begin with a roff control character" do
    expect(described_class.guard_control(".simplecov would be a macro here")).to start_with("\\&.")
  end
end
