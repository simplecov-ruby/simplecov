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

  # Run from a directory that is not the coverage path, so a history
  # written without one lands somewhere this example cleans up, and
  # somewhere the reads can tell apart from the real thing.
  # The removal happens out here, after the chdir has returned, because
  # Windows refuses to remove the directory the process still stands in.
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

  describe ".record", mutant_expression: ["SimpleCov::History*", "SimpleCov::History.record",
                                          "SimpleCov::History.read"] do
    it "appends an entry carrying totals, groups, files, and provenance" do
      described_class.record(result)

      entry = described_class.read.fetch(0)
      expect(entry.fetch("created_at")).to eq("2026-08-25T12:00:00Z")
      expect(entry.fetch("branch")).to eq("main")
      expect(entry.fetch("commit")).to eq("abc123def")
      expect(entry.fetch("totals")).to eq("line" => 87.5)
      expect(entry.fetch("groups")).to eq("Samples" => {"line" => 66.66}, "Ungrouped" => {"line" => 100.0})
      expect(entry.fetch("files")).to include("spec/fixtures/sample.rb" => {"line" => 100.0})
    end

    it "appends across runs, newest last" do
      described_class.record(result)
      described_class.record(result)

      entries = described_class.read
      expect(entries.length).to eq(2)
    end

    it "caps the history at the configured limit, dropping the oldest" do
      allow(SimpleCov).to receive(:history_limit).and_return(2)
      3.times do |index|
        result.created_at = Time.new(2026, 8, 25, 12, index, 0, "+00:00")
        described_class.record(result)
      end

      expect(described_class.read.map { |entry| entry.fetch("created_at") })
        .to eq(["2026-08-25T12:01:00Z", "2026-08-25T12:02:00Z"])
    end

    # The history is one of the coverage artifacts, and lives with them
    # rather than wherever the process happened to be started from.
    it "writes the history into the coverage directory" do
      described_class.record(result)

      expect(File.exist?(File.join(tmp, ".history.json"))).to be(true)
    end

    # The envelope is what tells a history from any other JSON file, and
    # the version is what a later format would be read against.
    it "writes the entries inside a versioned envelope" do
      described_class.record(result)

      envelope = JSON.parse(File.read(described_class.history_path)).fetch("simplecov_history")
      expect(envelope.fetch("format_version")).to eq(1)
      expect(envelope.fetch("entries").length).to eq(1)
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

      entry = described_class.read.fetch(0)
      expect(entry.fetch("totals")).to eq({})
      expect(entry.fetch("files").values).to all(eq({}))
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

      entry = described_class.read.fetch(0)
      expect(entry.fetch("totals")).to eq("line" => 66.66, "branch" => 50.0)
      expect(entry.fetch("files")).to eq(
        "spec/fixtures/json/sample.rb" => {"line" => 66.66, "branch" => 50.0}
      )
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

    it "answers empty, with a warning, for entries that are not a list" do
      File.write(described_class.history_path,
                 JSON.dump("simplecov_history" => {"entries" => {"nope" => 1}}))

      entries = nil
      stderr = capture_stderr { entries = described_class.read }

      expect(entries).to eq([])
      expect(stderr).to include(".history.json")
    end

    it "answers an empty history, silently, for a file of nothing but whitespace" do
      File.write(described_class.history_path, "\n  \n")

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

    it "appends an entry for the run, not the run itself" do
      entries = described_class.entries_with(result)

      expect(entries.last.fetch("created_at")).to eq("2026-08-25T12:00:00Z")
    end

    # The embedded history is what the report renders, and it is capped
    # the same way the recorded one is, keeping the newest.
    it "keeps the newest entries when the limit is reached" do
      allow(SimpleCov).to receive(:history_limit).and_return(2)
      2.times do |index|
        result.created_at = Time.new(2026, 8, 25, 12, index, 0, "+00:00")
        described_class.record(result)
      end
      result.created_at = Time.new(2026, 8, 25, 12, 9, 0, "+00:00")

      entries = described_class.entries_with(result)

      expect(entries.map { |entry| entry.fetch("created_at") })
        .to eq(["2026-08-25T12:01:00Z", "2026-08-25T12:09:00Z"])
    end

    # Criteria are named the way `.last_run.json` names them, which the
    # JSON round trip would hide by stringifying symbol keys anyway.
    it "names every criterion as a string, before anything is serialized" do
      entry = described_class.entries_with(result).last

      expect(entry.fetch("totals").keys).to eq(["line"])
      expect(entry.fetch("files").values.map(&:keys)).to all(eq(["line"]))
    end
  end

  describe ".git_info" do
    # A repository with a branch and a commit of its own, so the answers
    # are the ones this checkout would give and not the suite's.
    def checkout(dir)
      GitFixture.init_repo(dir, branch: "trunk")
      system("git", "-C", dir, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
      allow(described_class).to receive(:git_info).and_call_original
      allow(SimpleCov).to receive(:root).and_return(dir)
    end

    it "answers the checkout's own branch and commit" do
      Dir.mktmpdir("simplecov-history-branch-") do |dir|
        checkout(dir)

        branch, commit = described_class.git_info
        expect(branch).to eq("trunk")
        expect(commit).to match(/\A\h{40}\z/)
      end
    end

    # `SimpleCov.root` is whatever the project configured, and a path
    # object is as good an answer as a string.
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
        GitFixture.init_repo(dir)
        system("git", "-C", dir, "commit", "-q", "--allow-empty", "-m", "init", exception: true)
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
