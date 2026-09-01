# frozen_string_literal: true

require "helper"
require "tmpdir"
require "support/git_fixture"

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

  around do |example|
    elsewhere = File.join(tmp, "cwd")
    FileUtils.mkdir_p(elsewhere)
    Dir.chdir(elsewhere) { example.run }
  ensure
    FileUtils.remove_entry(tmp)
  end

  before do
    allow(SimpleCov).to receive(:coverage_path).and_return(tmp)
    allow(described_class).to receive(:git_info).and_return(%w[main abc123def])
  end

  def record_minutes(count)
    count.times do |index|
      result.created_at = Time.new(2026, 8, 25, 12, index, 0, "+00:00")
      described_class.record(result)
    end
  end

  def recorded_timestamps(entries)
    entries.map { |entry| entry.fetch("created_at") }
  end

  describe ".record", mutant_expression: ["SimpleCov::History*", "SimpleCov::History.record",
    "SimpleCov::History.read"] do
    let(:recorded_entry) do
      {
        "created_at" => "2026-08-25T12:00:00Z",
        "branch" => "main",
        "commit" => "abc123def",
        "totals" => {"line" => 87.5},
        "groups" => {"Samples" => {"line" => 66.66}, "Ungrouped" => {"line" => 100.0}},
        "files" => include("spec/fixtures/sample.rb" => {"line" => 100.0})
      }
    end

    let(:result_with_branch) do
      SimpleCov::Result.new(
        {
          source_fixture("json/sample.rb") => {
            "lines" => [1, 0, 1],
            "branches" => {[:if, 0, 1, 0, 3, 0] => {[:then, 1, 2, 2, 2, 6] => 1, [:else, 2, 3, 2, 3, 6] => 0}}
          }
        }
      ).tap { |r| r.created_at = Time.new(2026, 8, 25, 12, 0, 0, "+00:00") }
    end

    def envelope
      JSON.parse(File.read(described_class.history_path)).fetch("simplecov_history")
    end

    it "appends an entry carrying totals, groups, files, and provenance" do
      described_class.record(result)

      expect(described_class.read.fetch(0)).to include(recorded_entry)
    end

    it "appends across runs, newest last" do
      described_class.record(result)
      described_class.record(result)

      expect(described_class.read.length).to eq(2)
    end

    it "caps the history at the configured limit, dropping the oldest" do
      allow(SimpleCov).to receive(:history_limit).and_return(2)
      record_minutes(3)

      expect(recorded_timestamps(described_class.read)).to eq(["2026-08-25T12:01:00Z", "2026-08-25T12:02:00Z"])
    end

    it "writes the history into the coverage directory" do
      described_class.record(result)

      expect(File.exist?(File.join(tmp, ".history.json"))).to be(true)
    end

    it "writes the entries inside a versioned envelope" do
      described_class.record(result)

      expect(envelope.fetch("format_version")).to eq(1)
    end

    it "writes one entry per run into the envelope's list" do
      described_class.record(result)

      expect(envelope.fetch("entries").length).to eq(1)
    end

    it "records nothing when the limit is zero" do
      allow(SimpleCov).to receive(:history_limit).and_return(0)
      described_class.record(result)

      expect(File.exist?(described_class.history_path)).to be false
    end

    it "warns about a corrupt file" do
      File.write(described_class.history_path, "{")

      expect(capture_stderr { described_class.record(result) }).to include(".history.json")
    end

    it "starts fresh over a corrupt file" do
      File.write(described_class.history_path, "{")
      capture_stderr { described_class.record(result) }

      expect(described_class.read.length).to eq(1)
    end

    it "skips the totals for criteria the run did not measure, line included" do
      allow(SimpleCov).to receive_messages(line_coverage?: false)
      described_class.record(result)

      expect(described_class.read.fetch(0).fetch("totals")).to eq({})
    end

    it "skips the file figures for criteria the run did not measure, line included" do
      allow(SimpleCov).to receive_messages(line_coverage?: false)
      described_class.record(result)

      expect(described_class.read.fetch(0).fetch("files").values).to all(eq({}))
    end

    it "records the totals of every measured criterion" do
      allow(SimpleCov).to receive_messages(branch_coverage?: true)
      described_class.record(result_with_branch)

      expect(described_class.read.fetch(0).fetch("totals")).to eq("line" => 66.66, "branch" => 50.0)
    end

    it "records the file figures of every measured criterion" do
      allow(SimpleCov).to receive_messages(branch_coverage?: true)
      described_class.record(result_with_branch)

      expect(described_class.read.fetch(0).fetch("files"))
        .to eq("spec/fixtures/json/sample.rb" => {"line" => 66.66, "branch" => 50.0})
    end
  end

  describe ".read" do
    let(:non_list_entries) { JSON.dump("simplecov_history" => {"entries" => {"nope" => 1}}) }
    let(:not_a_history) { JSON.dump("something" => "else") }

    it "answers an empty history for a missing file" do
      expect(described_class.read).to eq([])
    end

    it "answers an empty history for an empty file" do
      File.write(described_class.history_path, "")

      expect(without_stderr { described_class.read }).to eq([])
    end

    it "stays silent over an empty file" do
      File.write(described_class.history_path, "")

      expect(capture_stderr { described_class.read }).to be_empty
    end

    it "answers an empty history for entries that are not a list" do
      File.write(described_class.history_path, non_list_entries)

      expect(without_stderr { described_class.read }).to eq([])
    end

    it "warns about entries that are not a list" do
      File.write(described_class.history_path, non_list_entries)

      expect(capture_stderr { described_class.read }).to include(".history.json")
    end

    it "answers an empty history for a file of nothing but whitespace" do
      File.write(described_class.history_path, "\n  \n")

      expect(without_stderr { described_class.read }).to eq([])
    end

    it "stays silent over a file of nothing but whitespace" do
      File.write(described_class.history_path, "\n  \n")

      expect(capture_stderr { described_class.read }).to be_empty
    end

    it "answers an empty history for a file that is not a history" do
      File.write(described_class.history_path, not_a_history)

      expect(without_stderr { described_class.read }).to eq([])
    end

    it "warns about a file that is not a history" do
      File.write(described_class.history_path, not_a_history)

      expect(capture_stderr { described_class.read }).to include(".history.json")
    end
  end

  describe ".entries_with" do
    it "returns the recorded entries plus the given run" do
      described_class.record(result)

      expect(described_class.entries_with(result).length).to eq(2)
    end

    it "leaves the history on disk alone" do
      described_class.record(result)
      described_class.entries_with(result)

      expect(described_class.read.length).to eq(1)
    end

    it "appends an entry for the run, not the run itself" do
      entries = described_class.entries_with(result)

      expect(entries.last.fetch("created_at")).to eq("2026-08-25T12:00:00Z")
    end

    it "keeps the newest entries when the limit is reached" do
      allow(SimpleCov).to receive(:history_limit).and_return(2)
      record_minutes(2)
      result.created_at = Time.new(2026, 8, 25, 12, 9, 0, "+00:00")

      expect(recorded_timestamps(described_class.entries_with(result)))
        .to eq(["2026-08-25T12:01:00Z", "2026-08-25T12:09:00Z"])
    end

    it "names every total's criterion as a string, before anything is serialized" do
      entry = described_class.entries_with(result).last

      expect(entry.fetch("totals").keys).to eq(["line"])
    end

    it "names every file's criterion as a string, before anything is serialized" do
      entry = described_class.entries_with(result).last

      expect(entry.fetch("files").values.map(&:keys)).to all(eq(["line"]))
    end
  end

  describe ".git_info" do
    def checkout(dir)
      GitFixture.init_repo(dir, branch: "trunk")
      system("git", "-C", dir, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
      allow(described_class).to receive(:git_info).and_call_original
      allow(SimpleCov).to receive(:root).and_return(dir)
    end

    def detached_checkout(dir)
      GitFixture.init_repo(dir)
      system("git", "-C", dir, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
      system("git", "-C", dir, "checkout", "-q", "--detach", exception: true)
      allow(described_class).to receive(:git_info).and_call_original
      allow(SimpleCov).to receive(:root).and_return(dir)
    end

    it "answers the checkout's own branch" do
      Dir.mktmpdir("simplecov-history-branch-") do |dir|
        checkout(dir)

        expect(described_class.git_info.first).to eq("trunk")
      end
    end

    it "answers the checkout's own commit" do
      Dir.mktmpdir("simplecov-history-branch-") do |dir|
        checkout(dir)

        expect(described_class.git_info.last).to match(/\A\h{40}\z/)
      end
    end

    it "takes a root that is not a string" do
      Dir.mktmpdir("simplecov-history-pathname-") do |dir|
        checkout(dir)
        allow(SimpleCov).to receive(:root).and_return(Pathname(dir))

        expect(described_class.git_info.first).to eq("trunk")
      end
    end

    it "answers nothing at all when git cannot be run" do
      allow(described_class).to receive(:git_info).and_call_original
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)

      expect(described_class.git_info).to eq([nil, nil])
    end

    it "returns nils outside a git checkout" do
      Dir.mktmpdir("simplecov-history-no-git-") do |dir|
        allow(described_class).to receive(:git_info).and_call_original
        allow(SimpleCov).to receive(:root).and_return(dir)

        expect(described_class.git_info).to eq([nil, nil])
      end
    end

    it "returns the commit inside one" do
      allow(described_class).to receive(:git_info).and_call_original

      expect(described_class.git_info.last).to match(/\A\h{40}\z/)
    end

    it "returns the branch inside one" do
      allow(described_class).to receive(:git_info).and_call_original

      expect(described_class.git_info.first).to be_a(String).or be_nil
    end

    it "reports a detached HEAD as no branch" do
      Dir.mktmpdir("simplecov-history-detached-") do |dir|
        detached_checkout(dir)

        expect(described_class.git_info.first).to be_nil
      end
    end

    it "still reports the commit of a detached HEAD" do
      Dir.mktmpdir("simplecov-history-detached-") do |dir|
        detached_checkout(dir)

        expect(described_class.git_info.last).to match(/\A\h{40}\z/)
      end
    end
  end
end
