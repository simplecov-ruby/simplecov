# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe SimpleCov::Formatter::JSONFormatter::ProductionSectionFormatter do
  let(:tmp) { Dir.mktmpdir("simplecov-production-section-spec-") }
  let(:path) { File.join(tmp, "production.json") }

  after { FileUtils.remove_entry(tmp) }

  def write_store(coverage:, last_seen: {}, started_at: "2026-08-01T05:00:00Z", updated_at: "2026-08-25T11:00:00Z")
    File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE => {
                                 "format_version" => 1,
                                 "started_at" => started_at, "updated_at" => updated_at,
                                 "coverage" => coverage, "last_seen" => last_seen
                               }))
  end

  it "returns nil when no store is configured" do
    expect(described_class.call(nil)).to be_nil
  end

  it "carries the window and each file's lines and stamp" do
    write_store(coverage: {"lib/b.rb" => [2], "lib/a.rb" => [1, 3]},
                last_seen: {"lib/a.rb" => "2026-08-25T10:00:00Z"})

    section = described_class.call(path)

    expect(section).to eq(
      started_at: "2026-08-01T05:00:00Z",
      updated_at: "2026-08-25T11:00:00Z",
      files: {
        "lib/a.rb" => {lines: [1, 3], last_seen: "2026-08-25T10:00:00Z"},
        "lib/b.rb" => {lines: [2]}
      }
    )
  end

  it "omits a window the store does not carry" do
    write_store(coverage: {"lib/a.rb" => [1]}, started_at: nil, updated_at: nil)

    expect(described_class.call(path).keys).to eq([:files])
  end

  # The store lives outside the repository and outside the suite's
  # control; a missing or corrupt night of data must not fail the run
  # that measured the tests.
  it "warns and returns nil when the store is missing" do
    section = nil
    stderr = capture_stderr { section = described_class.call(path) }

    expect(section).to be_nil
    expect(stderr).to include("production coverage")
  end

  it "warns and returns nil when the store is not a production coverage file" do
    File.write(path, JSON.dump("wrong" => true))

    section = nil
    stderr = capture_stderr { section = described_class.call(path) }

    expect(section).to be_nil
    expect(stderr).to include(path)
  end
end
