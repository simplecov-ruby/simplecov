# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe SimpleCov::Formatter::JSONFormatter::ProductionSectionFormatter do
  let(:tmp) { Dir.mktmpdir("simplecov-production-section-spec-") }
  let(:path) { File.join(tmp, "production.json") }

  let(:one_file_section) do
    {
      started_at: "2026-08-01T05:00:00Z",
      updated_at: "2026-08-25T11:00:00Z",
      files: {"lib/a.rb" => {lines: [1]}}
    }
  end
  let(:two_file_section) do
    {
      started_at: "2026-08-01T05:00:00Z",
      updated_at: "2026-08-25T11:00:00Z",
      files: {
        "lib/a.rb" => {lines: [1, 3], last_seen: "2026-08-25T10:00:00Z"},
        "lib/b.rb" => {lines: [2]}
      }
    }
  end

  after { FileUtils.remove_entry(tmp) }

  def write_store(coverage:, last_seen: {}, started_at: "2026-08-01T05:00:00Z", updated_at: "2026-08-25T11:00:00Z")
    File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE => {
      "format_version" => 1,
      "started_at" => started_at, "updated_at" => updated_at,
      "coverage" => coverage, "last_seen" => last_seen
    }))
  end

  def write_windowless_store(coverage:)
    File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE => {
      "format_version" => 1, "coverage" => coverage, "last_seen" => {}
    }))
  end

  it "returns nil when no store is configured" do
    expect(described_class.call(nil)).to be_nil
  end

  it "reads the configured store when called without a path" do
    write_store(coverage: {"lib/a.rb" => [1]})
    allow(SimpleCov).to receive(:production_coverage).and_return(path)

    expect(described_class.call).to eq(one_file_section)
  end

  it "returns nil when no store is configured and no path is given" do
    allow(SimpleCov).to receive(:production_coverage).and_return(nil)

    expect(described_class.call).to be_nil
  end

  it "carries the window and each file's lines and stamp" do
    write_store(coverage: {"lib/b.rb" => [2], "lib/a.rb" => [1, 3]},
      last_seen: {"lib/a.rb" => "2026-08-25T10:00:00Z"})

    expect(described_class.call(path)).to eq(two_file_section)
  end

  it "orders the files by path" do
    write_store(coverage: {"lib/c.rb" => [3], "lib/a.rb" => [1], "lib/b.rb" => [2]})

    expect(described_class.call(path).fetch(:files).keys).to eq(%w[lib/a.rb lib/b.rb lib/c.rb])
  end

  it "omits a window the store carries as null" do
    write_store(coverage: {"lib/a.rb" => [1]}, started_at: nil, updated_at: nil)

    expect(described_class.call(path)).to eq(files: {"lib/a.rb" => {lines: [1]}})
  end

  it "omits a window the store has no key for" do
    write_windowless_store(coverage: {"lib/a.rb" => [1]})

    expect(described_class.call(path)).to eq(files: {"lib/a.rb" => {lines: [1]}})
  end

  context "when the store is missing" do
    it "returns nil" do
      expect(without_stderr { described_class.call(path) }).to be_nil
    end

    it "warns" do
      expect(capture_stderr { described_class.call(path) }).to include("production coverage")
    end
  end

  context "when the store is not a production coverage file" do
    before { File.write(path, JSON.dump("wrong" => true)) }

    it "returns nil" do
      expect(without_stderr { described_class.call(path) }).to be_nil
    end

    it "warns, naming the file it skipped" do
      expect(capture_stderr { described_class.call(path) }).to eq(
        "[SimpleCov] skipping production coverage (#{path} is not a SimpleCov production coverage file)\n"
      )
    end
  end
end
