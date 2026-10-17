# frozen_string_literal: true

require "helper"
require_relative "../tasks/release_notes"

RSpec.describe ReleaseNotes do
  let(:changelog) do
    <<~MD
      # Changelog

      ## [Unreleased]

      ## [1.2.0] - 2026-09-02

      ### Added

      - Newest. See [#2].

      ## [1.1.1] - 2026-08-12

      ### Fixed

      - Older. Thanks [@someone].

      [Unreleased]: https://github.com/simplecov-ruby/simplecov/compare/v1.2.0...HEAD
      [1.2.0]: https://github.com/simplecov-ruby/simplecov/compare/v1.1.1...v1.2.0
      [1.1.1]: https://github.com/simplecov-ruby/simplecov/releases/tag/v1.1.1

      [#2]: https://github.com/simplecov-ruby/simplecov/issues/2

      [@someone]: https://github.com/someone
    MD
  end

  it "returns the version's section without its heading, with the link definitions it uses" do
    expect(described_class.for("1.2.0", changelog))
      .to eq("### Added\n\n- Newest. See [#2].\n\n[#2]: https://github.com/simplecov-ruby/simplecov/issues/2\n")
  end

  it "finds the last section without swallowing the link definitions" do
    expect(described_class.for("1.1.1", changelog))
      .to eq("### Fixed\n\n- Older. Thanks [@someone].\n\n[@someone]: https://github.com/someone\n")
  end

  it "carries no link definitions for a section that uses none" do
    plain = <<~MD
      ## [1.0.0] - 2026-01-01

      ### Added

      - Plain.

      [1.0.0]: https://github.com/simplecov-ruby/simplecov/releases/tag/v1.0.0
    MD

    expect(described_class.for("1.0.0", plain)).to eq("### Added\n\n- Plain.\n")
  end

  it "raises for a version the changelog does not have" do
    expect { described_class.for("9.9.9", changelog) }.to raise_error(ArgumentError, /9\.9\.9/)
  end

  it "does not mistake a version for a prefix of another" do
    expect { described_class.for("1.2", changelog) }.to raise_error(ArgumentError, /1\.2/)
  end

  it "reads the project changelog by default" do
    expect(described_class.for(SimpleCov::VERSION)).to start_with("### ")
  end
end
