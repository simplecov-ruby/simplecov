# frozen_string_literal: true

require "helper"
require "simplecov/coverage_json"

RSpec.describe SimpleCov::CoverageJSON do
  let(:directory) { Dir.mktmpdir("simplecov-coverage-json-spec-") }
  let(:path) { File.join(directory, "coverage.json") }

  after { FileUtils.remove_entry(directory) }

  it "loads an object from valid UTF-8 JSON" do
    File.binwrite(path, JSON.dump("coverage" => {}).encode(Encoding::UTF_8))

    expect(described_class.load(path)).to eq("coverage" => {})
  end

  it "rejects malformed JSON with one domain error" do
    File.binwrite(path, "{")

    expect { described_class.load(path) }.to raise_error(described_class::Error, /unexpected|expected/i)
  end

  it "rejects invalid UTF-8 before parsing" do
    File.binwrite(path, "{\"source\":\"\xFF\"}".b)

    expect { described_class.load(path) }.to raise_error(described_class::Error, /not valid UTF-8/)
  end

  ["null", "[]"].each do |document|
    it "rejects a #{document} root" do
      File.binwrite(path, document)

      expect { described_class.load(path) }.to raise_error(described_class::Error, /top-level value must be an object/)
    end
  end
end
