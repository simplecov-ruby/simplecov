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

  it "creates the directory and writes the envelope on first store" do
    sink.store("lib/a.rb" => [3, 1].sort)

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

  it "refuses a file that is not JSON at all" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "not json")

    expect { sink.store("lib/a.rb" => [1]) }
      .to raise_error(SimpleCov::Production::Error, /not valid JSON/)
  end

  it "treats an empty file as a fresh store" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")

    sink.store("lib/a.rb" => [1])
    expect(stored["coverage"]).to eq("lib/a.rb" => [1])
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
