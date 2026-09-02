# frozen_string_literal: true

require "helper"
require_relative "../tasks/release_notes"

RSpec.describe ReleaseNotes do
  let(:changelog) do
    <<~MD
      1.2.0 (2026-09-02)
      ==================

      ## Highlights
      * Newest.

      1.1.1 (2026-08-12)
      ==================

      ## Bugfixes
      * Older.
    MD
  end

  it "returns the version's section without its heading" do
    expect(described_class.for("1.2.0", changelog)).to eq("## Highlights\n* Newest.\n")
  end

  it "finds a section that is not the first" do
    expect(described_class.for("1.1.1", changelog)).to eq("## Bugfixes\n* Older.\n")
  end

  it "raises for a version the changelog does not have" do
    expect { described_class.for("9.9.9", changelog) }.to raise_error(ArgumentError, /9\.9\.9/)
  end

  it "reads the project changelog by default" do
    expect(described_class.for(SimpleCov::VERSION)).to include("## Enhancements")
  end
end
