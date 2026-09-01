# frozen_string_literal: true

require "helper"
require "simplecov/production"

RSpec.describe SimpleCov::Production::FileSink do
  subject(:sink) { described_class.new(path: path) }

  let(:tmp) { Dir.mktmpdir("simplecov-file-sink-spec-") }
  let(:path) { File.join(tmp, "nested", "production.json") }

  let(:long_document) do
    {"format_version" => 1,
     "coverage" => {"lib/a.rb" => [1, 2, 3, 4, 5],
                    "lib/b.rb" => [1, 2, 3, 4, 5],
                    "lib/c.rb" => [1, 2, 3, 4, 5]},
     "last_seen" => {}}
  end

  after { FileUtils.remove_entry(tmp) }

  def stored
    described_class.read(path)
  end

  def write_envelope(inner, pretty: false)
    document = {described_class::ENVELOPE => inner}
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, pretty ? JSON.pretty_generate(document) : JSON.dump(document))
  end

  describe "#locked" do
    let(:probes) do
      sink.send(:with_exclusive_lock) do |_file|
        File.open(path) do |probe|
          {exclusive: probe.flock(File::LOCK_EX | File::LOCK_NB),
           shared: probe.flock(File::LOCK_SH | File::LOCK_NB)}
        end
      end
    end

    before { FileUtils.mkdir_p(File.dirname(path)) }

    it "refuses another exclusive flock while the block runs" do
      expect(probes[:exclusive]).to be(false)
    end

    it "refuses a shared flock while the block runs" do
      expect(probes[:shared]).to be(false)
    end

    it "yields a handle open for reading and writing" do
      sink.send(:with_exclusive_lock) do |file|
        file.write("x")
        file.rewind
        expect(file.read).to eq("x")
      end
    end

    it "answers whatever the block answered" do
      expect(sink.send(:with_exclusive_lock) { |_file| :stored }).to be(:stored)
    end

    it "creates the store world-readable and owner-writable" do
      previous = File.umask(0)
      sink.send(:with_exclusive_lock) { |_file| nil }

      expect(File.stat(path).mode & 0o777).to eq(0o644)
    ensure
      File.umask(previous)
    end

    it "opens the store as a file even when its path starts with a pipe" do
      skip "a pipe is not a legal filename character on Windows" if Gem.win_platform?

      allow(sink).to receive(:path).and_return("|true") # rubocop:disable RSpec/SubjectStub

      Dir.chdir(tmp) { sink.send(:with_exclusive_lock) { |_file| nil } }

      expect(File).to exist(File.join(tmp, "|true"))
    end
  end

  it "resolves its path once, up front" do
    expect(described_class.new(path: "tmp/production.json").path)
      .to eq(File.expand_path("tmp/production.json"))
  end

  it "answers true from the first store" do
    expect(sink.store("lib/a.rb" => [3, 1].sort)).to be(true)
  end

  it "writes the format version on first store" do
    sink.store("lib/a.rb" => [3, 1].sort)

    expect(stored["format_version"]).to eq(1)
  end

  it "creates the directory and writes the coverage on first store" do
    sink.store("lib/a.rb" => [3, 1].sort)

    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 3])
  end

  it "stamps the window's beginning on first store" do
    sink.store("lib/a.rb" => [3, 1].sort)

    expect(stored["started_at"]).not_to be_nil
  end

  it "stamps the update time on first store" do
    sink.store("lib/a.rb" => [3, 1].sort)

    expect(stored["updated_at"]).not_to be_nil
  end

  it "union-merges into an existing store" do
    sink.store("lib/a.rb" => [1, 3])
    sink.store("lib/a.rb" => [3, 5], "lib/b.rb" => [2])

    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 3, 5], "lib/b.rb" => [2])
  end

  it "preserves started_at when it merges into an existing store" do
    sink.store("lib/a.rb" => [1, 3])
    first_started = stored["started_at"]

    sink.store("lib/a.rb" => [3, 5], "lib/b.rb" => [2])

    expect(stored["started_at"]).to eq(first_started)
  end

  it "sorts the lines it merges into a file" do
    sink.store("lib/a.rb" => [5, 9])
    sink.store("lib/a.rb" => [1, 7])

    expect(stored["coverage"]).to eq("lib/a.rb" => [1, 5, 7, 9])
  end

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

  it "leaves valid JSON after truncating a document that used to be longer" do
    write_envelope(long_document, pretty: true)

    sink.store("lib/a.rb" => [1])

    expect { JSON.parse(File.read(path)) }.not_to raise_error
  end

  it "keeps the untouched files of a document that used to be longer" do
    write_envelope(long_document, pretty: true)

    sink.store("lib/a.rb" => [1])

    expect(stored["coverage"]).to include("lib/c.rb" => [1, 2, 3, 4, 5])
  end

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
  end

  it "leaves a JSON file that is not a production store as it found it" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.dump("coverage" => {}))

    suppress(SimpleCov::Production::Error) { sink.store("lib/a.rb" => [1]) }

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

  it "treats a whitespace-only file as a fresh store" do
    FileUtils.mkdir_p(File.dirname(path))
    ["\n", "   ", " \n\t ", "\n  "].each { |blank| expect_fresh_store_for(blank) }
  end

  def expect_fresh_store_for(blank)
    File.write(path, blank)
    expect { sink.store("lib/a.rb" => [1]) }.not_to raise_error
    expect(stored["coverage"]).to eq("lib/a.rb" => [1])
  end

  it "starts a fresh store with an unset window beginning" do
    fresh = described_class.parse("", path)

    expect(fresh).to eq("coverage" => {}, "last_seen" => {}, "started_at" => nil)
  end

  it "names the file and the reason when the JSON will not parse" do
    expect { described_class.parse("{ nope", path) }
      .to raise_error(SimpleCov::Production::Error,
        /\A#{Regexp.escape(path)} is not valid JSON \(.+\)\z/)
  end

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

  it "replaces a non-object coverage or last_seen table with an empty one" do
    document = JSON.dump(described_class::ENVELOPE => {"coverage" => "junk", "last_seen" => 42})

    expect(described_class.parse(document, path))
      .to include("coverage" => {}, "last_seen" => {})
  end

  describe "last_seen" do
    let(:old_stamp) { Time.utc(2026, 3, 1).iso8601 }

    it "stamps every file in a delta" do
      sink.store("lib/a.rb" => [1], "lib/b.rb" => [2])

      expect(stored["last_seen"].keys.sort).to eq(["lib/a.rb", "lib/b.rb"])
    end

    it "stamps a delta with the store time" do
      sink.store("lib/a.rb" => [1], "lib/b.rb" => [2])

      expect(Time.iso8601(stored["last_seen"]["lib/a.rb"])).to be_within(60).of(Time.now)
    end

    it "keeps the stamp of a file the delta leaves alone" do
      expect(last_seen_after_partial_delta["lib/a.rb"]).to eq(old_stamp)
    end

    it "advances the stamp of a file the delta touches" do
      expect(last_seen_after_partial_delta["lib/b.rb"]).not_to eq(old_stamp)
    end

    it "sorts the stamps so the store diffs stably" do
      sink.store("lib/z.rb" => [1])
      sink.store("lib/a.rb" => [1])

      expect(stored["last_seen"].keys).to eq(["lib/a.rb", "lib/z.rb"])
    end

    it "reads stamps that are not a table as no stamps at all" do
      write_store_without_stamps

      expect(stored["last_seen"]).to eq({})
    end

    it "keeps the coverage of a store without stamps" do
      write_store_without_stamps
      sink.store("lib/b.rb" => [2])

      expect(stored["coverage"]).to eq("lib/a.rb" => [1], "lib/b.rb" => [2])
    end

    it "stamps only the delta when the store had no stamps" do
      write_store_without_stamps
      sink.store("lib/b.rb" => [2])

      expect(stored["last_seen"].keys).to eq(["lib/b.rb"])
    end

    def last_seen_after_partial_delta
      sink.store("lib/a.rb" => [1], "lib/b.rb" => [2])
      rewrite_last_seen("lib/a.rb" => old_stamp, "lib/b.rb" => old_stamp)
      sink.store("lib/b.rb" => [9])
      stored["last_seen"]
    end

    def write_store_without_stamps
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.dump(SimpleCov::Production::FileSink::ENVELOPE =>
        {"format_version" => 1, "coverage" => {"lib/a.rb" => [1]}, "last_seen" => "junk"}))
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
