# frozen_string_literal: true

require "helper"
require "tmpdir"

RSpec.describe SimpleCov::History do
  let(:tmp) { Dir.mktmpdir("simplecov-history-spec-") }

  let(:result) do
    SimpleCov::Result.new(
      {
        source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
        source_fixture("json/sample.rb") => {"lines" => [1, 0, 1]}
      },
      filter_config: SimpleCov::Result::FilterConfig.new(
        filters: [], groups: {"Samples" => SimpleCov::StringFilter.new("json")}
      )
    ).tap { |r| r.created_at = Time.new(2026, 8, 25, 12, 0, 0, "+00:00") }
  end

  before do
    allow(SimpleCov).to receive(:coverage_path).and_return(tmp)
    allow(described_class).to receive(:git_info).and_return(%w[main abc123def])
  end

  after { FileUtils.remove_entry(tmp) }

  describe ".record" do
    it "appends an entry carrying totals, groups, files, and provenance" do
      described_class.record(result)

      entry = described_class.read.fetch(0)
      expect(entry.fetch("created_at")).to eq("2026-08-25T12:00:00Z")
      expect(entry.fetch("branch")).to eq("main")
      expect(entry.fetch("commit")).to eq("abc123def")
      expect(entry.fetch("totals")).to eq("line" => 87.5)
      expect(entry.fetch("groups")).to eq("Samples" => {"line" => 66.66}, "Ungrouped" => {"line" => 100.0})
      expect(entry.fetch("files")).to include("spec/fixtures/sample.rb" => 100.0)
    end

    it "appends across runs, newest last" do
      described_class.record(result)
      described_class.record(result)

      entries = described_class.read
      expect(entries.length).to eq(2)
    end

    it "caps the history at the configured limit, dropping the oldest" do
      allow(SimpleCov).to receive(:history_limit).and_return(2)
      3.times { described_class.record(result) }

      expect(described_class.read.length).to eq(2)
    end

    it "records nothing when the limit is zero" do
      allow(SimpleCov).to receive(:history_limit).and_return(0)
      described_class.record(result)

      expect(File.exist?(described_class.history_path)).to be false
    end

    it "starts fresh over a corrupt file, with a warning" do
      File.write(described_class.history_path, "{")

      stderr = capture_stderr { described_class.record(result) }

      expect(stderr).to include(".history.json")
      expect(described_class.read.length).to eq(1)
    end

    it "skips criteria the run did not measure, line included" do
      allow(SimpleCov).to receive_messages(line_coverage?: false)

      described_class.record(result)

      expect(described_class.read.fetch(0).fetch("totals")).to eq({})
    end

    it "records measured criteria only" do
      allow(SimpleCov).to receive_messages(branch_coverage?: true)
      result_with_branch = SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {
            "lines" => [1, 0, 1],
            "branches" => {[:if, 0, 1, 0, 3, 0] => {[:then, 1, 2, 2, 2, 6] => 1, [:else, 2, 3, 2, 3, 6] => 0}}
          }
        }
      )
      result_with_branch.created_at = Time.new(2026, 8, 25, 12, 0, 0, "+00:00")

      described_class.record(result_with_branch)

      expect(described_class.read.fetch(0).fetch("totals")).to eq("line" => 66.66, "branch" => 50.0)
    end
  end

  describe ".read" do
    it "answers an empty history for a missing file" do
      expect(described_class.read).to eq([])
    end

    it "answers an empty history, silently, for an empty file" do
      File.write(described_class.history_path, "")

      expect(capture_stderr { expect(described_class.read).to eq([]) }).to be_empty
    end

    it "answers empty, with a warning, for a file that is not a history" do
      File.write(described_class.history_path, JSON.dump("something" => "else"))

      entries = nil
      stderr = capture_stderr { entries = described_class.read }

      expect(entries).to eq([])
      expect(stderr).to include(".history.json")
    end
  end

  describe ".entries_with" do
    it "returns the recorded entries plus the given run, capped, without writing" do
      described_class.record(result)

      entries = described_class.entries_with(result)

      expect(entries.length).to eq(2)
      expect(described_class.read.length).to eq(1)
    end
  end

  describe ".git_info" do
    it "returns nils outside a git checkout" do
      Dir.mktmpdir("simplecov-history-no-git-") do |dir|
        allow(described_class).to receive(:git_info).and_call_original
        allow(SimpleCov).to receive(:root).and_return(dir)

        expect(described_class.git_info).to eq([nil, nil])
      end
    end

    it "returns the branch and commit inside one" do
      allow(described_class).to receive(:git_info).and_call_original

      branch, commit = described_class.git_info
      expect(commit).to match(/\A\h{40}\z/)
      expect(branch).to be_a(String).or be_nil
    end

    # CI checkouts are usually detached; the literal "HEAD" git reports
    # there is not a branch and must not be recorded as one.
    it "reports a detached HEAD as no branch" do
      Dir.mktmpdir("simplecov-history-detached-") do |dir|
        system("git", "-C", dir, "init", "-q", "-b", "main", exception: true)
        system("git", "-C", dir, "-c", "user.email=spec@example.com", "-c", "user.name=spec",
               "commit", "-q", "--allow-empty", "-m", "init", exception: true)
        system("git", "-C", dir, "checkout", "-q", "--detach", exception: true)
        allow(described_class).to receive(:git_info).and_call_original
        allow(SimpleCov).to receive(:root).and_return(dir)

        branch, commit = described_class.git_info
        expect(branch).to be_nil
        expect(commit).to match(/\A\h{40}\z/)
      end
    end
  end
end
