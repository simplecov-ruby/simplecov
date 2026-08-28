# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe SimpleCov::Production::FileSink do
  subject(:sink) { described_class.new(path: path) }

  let(:tmp) { Dir.mktmpdir("simplecov-file-sink-spec-") }
  let(:path) { File.join(tmp, "nested", "production.json") }

  after { FileUtils.remove_entry(tmp) }

  def stored
    described_class.read(path)
  end

  # Put a document on disk for the sink to find.
  def write_envelope(inner, pretty: false)
    document = {described_class::ENVELOPE => inner}
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, pretty ? JSON.pretty_generate(document) : JSON.dump(document))
  end

  describe "#locked" do
    before { FileUtils.mkdir_p(File.dirname(path)) }

    # flock contention is per open file description, so a second handle
    # in this very process can observe the lock the first one holds.
    it "holds an exclusive flock on the store while the block runs" do
      sink.send(:locked) do |_file|
        File.open(path) do |probe|
          expect(probe.flock(File::LOCK_EX | File::LOCK_NB)).to be(false)
          expect(probe.flock(File::LOCK_SH | File::LOCK_NB)).to be(false)
        end
      end
    end

    it "yields a handle open for reading and writing, and answers the block" do
      result = sink.send(:locked) do |file|
        file.write("x")
        file.rewind
        expect(file.read).to eq("x")
        :stored
      end

      expect(result).to be(:stored)
    end

    # The mode is asked about here as well as through `store`, because
    # these examples are the whole of this subject's test pool.
    it "creates the store world-readable and owner-writable" do
      previous = File.umask(0)
      sink.send(:locked) { |_file| nil }

      expect(File.stat(path).mode & 0o777).to eq(0o644)
    ensure
      File.umask(previous)
    end

    # `Kernel#open` reads a leading pipe as a command to run; `File.open`
    # reads it as a filename. The store must be a file.
    it "opens the store as a file even when its path starts with a pipe" do
      skip "a pipe is not a legal filename character on Windows" if Gem.win_platform?

      # The constructor absolutizes every path, so a leading pipe can
      # only be arranged by standing in for the reader.
      allow(sink).to receive(:path).and_return("|true") # rubocop:disable RSpec/SubjectStub

      Dir.chdir(tmp) { sink.send(:locked) { |_file| nil } }

      expect(File).to exist(File.join(tmp, "|true"))
    end
  end

  # The sink is usually configured from a relative path in a deploy
  # script, and a worker that chdirs must still write the same file.
  it "resolves its path once, up front" do
    expect(described_class.new(path: "tmp/production.json").path)
      .to eq(File.expand_path("tmp/production.json"))
  end

  it "creates the directory and writes the envelope on first store" do
    expect(sink.store("lib/a.rb" => [3, 1].sort)).to be(true)

    expect(stored["format_version"]).to eq(1)
    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 3])
    expect(stored["started_at"]).not_to be_nil
    expect(stored["updated_at"]).not_to be_nil
  end

  it "union-merges into an existing store, preserving started_at" do
    sink.store("lib/a.rb" => [1, 3])
    first_started = stored["started_at"]

    sink.store("lib/a.rb" => [3, 5], "lib/b.rb" => [2])

    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 3, 5], "lib/b.rb" => [2])
    expect(stored["started_at"]).to eq(first_started)
  end

  # A union puts the newcomers at the end, wherever they belong, and a
  # store nobody can diff is a store nobody reviews.
  it "sorts the lines it merges into a file" do
    sink.store("lib/a.rb" => [5, 9])
    sink.store("lib/a.rb" => [1, 7])

    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 5, 7, 9])
  end

  # The window's beginning is stamped once and carried forward: it is
  # what the dead-code report describes when it says how long it looked.
  it "keeps the window's beginning across stores" do
    write_envelope({"format_version" => 1, "started_at" => "2020-01-01T00:00:00Z",
                    "coverage" => {}, "last_seen" => {}})

    sink.store("lib/a.rb" => [1])

    expect(stored["started_at"]).to eq("2020-01-01T00:00:00Z")
  end

  it "stamps the store in UTC, whatever the machine's clock says" do
    allow(Time).to receive(:now).and_return(Time.new(2026, 3, 1, 12, 0, 0, "+05:00"))

    sink.store("lib/a.rb" => [1])

    expect(stored["updated_at"]).to eq("2026-03-01T07:00:00Z")
  end

  # Written in place under the lock, so a document that shrinks has to
  # take its old tail with it rather than leave trailing JSON behind.
  it "truncates a document that used to be longer" do
    write_envelope({"format_version" => 1,
                    "coverage" => {"lib/a.rb" => [1, 2, 3, 4, 5],
                                   "lib/b.rb" => [1, 2, 3, 4, 5],
                                   "lib/c.rb" => [1, 2, 3, 4, 5]},
                    "last_seen" => {}}, pretty: true)

    sink.store("lib/a.rb" => [1])

    expect { JSON.parse(File.read(path)) }.not_to raise_error
    expect(stored["coverage"]).to include("lib/c.rb" => [1, 2, 3, 4, 5])
  end

  # A store shared by every process on the host is read by all of them
  # and written by none but its owner.
  it "creates the store world-readable and owner-writable" do
    previous = File.umask(0)
    sink.store("lib/a.rb" => [1])

    expect(File.stat(path).mode & 0o777).to eq(0o644)
  ensure
    File.umask(previous)
  end

  it "sorts the files so the store diffs stably" do
    sink.store("lib/z.rb" => [1])
    sink.store("lib/a.rb" => [1])

    expect(stored["coverage"].keys).to eq(["lib/a.rb", "lib/z.rb"])
  end

  it "refuses to clobber a JSON file that is not a production store" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.dump("coverage" => {}))

    expect { sink.store("lib/a.rb" => [1]) }
      .to raise_error(SimpleCov::Production::Error, /not a SimpleCov production coverage file/)
    expect(File.read(path)).to eq(JSON.dump("coverage" => {}))
  end

  it "refuses valid JSON that is not an object" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "[1, 2]")

    expect { sink.store("lib/a.rb" => [1]) }
      .to raise_error(SimpleCov::Production::Error, /not a SimpleCov production coverage file/)
  end

  it "refuses a file that is not JSON at all, naming it" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "not json")

    expect { sink.store("lib/a.rb" => [1]) }
      .to raise_error(SimpleCov::Production::Error, /\A#{Regexp.escape(path)} is not valid JSON/)
  end

  it "treats an empty file as a fresh store" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")

    sink.store("lib/a.rb" => [1])
    expect(stored["coverage"]).to eq("lib/a.rb" => [1])
  end

  # A file holding only whitespace is empty too, from either end: a
  # half-written store must not be read as valid JSON.
  it "treats a whitespace-only file as a fresh store" do
    FileUtils.mkdir_p(File.dirname(path))
    ["\n", "   ", " \n\t ", "\n  "].each do |blank|
      File.write(path, blank)
      expect { sink.store("lib/a.rb" => [1]) }.not_to raise_error
      expect(stored["coverage"]).to eq("lib/a.rb" => [1])
    end
  end

  # The fresh store carries the started_at key, unset: the window's
  # beginning is stamped on the first write, and the dead-code report
  # reads that key to describe the window it is judging.
  it "starts a fresh store with an unset window beginning" do
    fresh = described_class.parse("", path)

    expect(fresh).to eq("coverage" => {}, "last_seen" => {}, "started_at" => nil)
  end

  it "names the file and the reason when the JSON will not parse" do
    expect { described_class.parse("{ nope", path) }
      .to raise_error(SimpleCov::Production::Error,
                      /\A#{Regexp.escape(path)} is not valid JSON \(.+\)\z/)
  end

  # Some parsers quote the whole document back at you. One line of that
  # is a diagnosis; the rest is the file you already have.
  it "keeps the first line of a complaint that runs long" do
    allow(JSON).to receive(:parse).and_raise(JSON::ParserError, "unexpected token\nat '{ nope'\n")

    expect { described_class.parse("{ nope", path) }
      .to raise_error(SimpleCov::Production::Error, "#{path} is not valid JSON (unexpected token)")
  end

  it "still names the file when the complaint says nothing at all" do
    allow(JSON).to receive(:parse).and_raise(JSON::ParserError, "")

    expect { described_class.parse("{ nope", path) }
      .to raise_error(SimpleCov::Production::Error, "#{path} is not valid JSON ()")
  end

  it "refuses a document whose envelope key holds something else" do
    write_envelope("nonsense")

    expect { described_class.read(path) }
      .to raise_error(SimpleCov::Production::Error, /not a SimpleCov production coverage file/)
  end

  # An envelope whose tables are the wrong shape is repaired rather
  # than refused: the file is a production store, just a damaged one.
  it "replaces a non-object coverage or last_seen table with an empty one" do
    document = JSON.dump(described_class::ENVELOPE => {"coverage" => "junk", "last_seen" => 42})

    expect(described_class.parse(document, path))
      .to include("coverage" => {}, "last_seen" => {})
  end

  # Oneshot clears on drain, so hot code re-reports every interval and
  # the store can keep a per-file recency stamp essentially for free.
  # "This file last mattered in March" is far stronger deletion evidence
  # than a binary bit over the whole window.
  describe "last_seen" do
    it "stamps every file in a delta with the store time" do
      sink.store("lib/a.rb" => [1], "lib/b.rb" => [2])

      expect(stored["last_seen"].keys.sort).to eq(["lib/a.rb", "lib/b.rb"])
      expect(Time.iso8601(stored["last_seen"]["lib/a.rb"])).to be_within(60).of(Time.now)
    end

    it "advances only the files the delta touches" do
      old = Time.utc(2026, 3, 1).iso8601
      sink.store("lib/a.rb" => [1], "lib/b.rb" => [2])
      rewrite_last_seen("lib/a.rb" => old, "lib/b.rb" => old)

      sink.store("lib/b.rb" => [9])

      expect(stored["last_seen"]["lib/a.rb"]).to eq(old)
      expect(stored["last_seen"]["lib/b.rb"]).not_to eq(old)
    end

    it "sorts the stamps so the store diffs stably" do
      sink.store("lib/z.rb" => [1])
      sink.store("lib/a.rb" => [1])

      expect(stored["last_seen"].keys).to eq(["lib/a.rb", "lib/z.rb"])
    end

    # A store written by an older gem (or a remote sink that only fills
    # the documented v1 shape) carries no stamps; reading and merging
    # into it must not require them.
    it "tolerates a store without stamps" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE =>
        {"format_version" => 1, "coverage" => {"lib/a.rb" => [1]}, "last_seen" => "junk"}))

      expect(stored["last_seen"]).to eq({})

      sink.store("lib/b.rb" => [2])
      expect(stored["coverage"]).to eq("lib/a.rb" => [1], "lib/b.rb" => [2])
      expect(stored["last_seen"].keys).to eq(["lib/b.rb"])
    end

    def rewrite_last_seen(stamps)
      document = JSON.parse(File.read(path))
      document[SimpleCov::Production::FileSink::ENVELOPE]["last_seen"] = stamps
      File.write(path, JSON.dump(document))
    end
  end

  describe ".read" do
    it "raises for a missing envelope, naming the path" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.dump("something" => "else"))

      expect { described_class.read(path) }
        .to raise_error(SimpleCov::Production::Error, /#{Regexp.escape(path)}/)
    end

    it "returns an empty coverage table when the envelope carries none" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE => {"format_version" => 1}))

      expect(described_class.read(path)["coverage"]).to eq({})
    end
  end
end
