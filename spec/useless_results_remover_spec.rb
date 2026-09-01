# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::UselessResultsRemover do
  subject(:remover) do
    described_class.call(result_set)
  end

  let(:gem_file_path) { "usr/bin/lib/2.5.0/gems/sample-gem/sample.rb" }
  let(:source_path) { source_fixture("app/models/user.rb") }

  let(:result_set) do
    {
      gem_file_path => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}}
      },
      source_path => {
        "lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        "branches" => {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}}
      }
    }
  end

  it "Result ignore gem file path from result set" do
    expect(result_set[gem_file_path]).to be_a(Hash)
    expect(remover).not_to have_key(gem_file_path)
  end

  it "still retains the app path" do
    expect(remover).to have_key(source_path)
    expect(remover[source_path]["lines"]).to be_a(Array)
  end

  it "keeps the legacy root_regx helper as an alias, warning about the spelling" do
    allow(SimpleCov::Deprecation).to receive(:warn)

    expect(described_class.root_regx).to eq(described_class.root_regex)
    expect(SimpleCov::Deprecation).to have_received(:warn).with(
      "`SimpleCov::UselessResultsRemover.root_regx` is deprecated. Replace with `root_regex`."
    )
  end

  context "when SimpleCov.root is the filesystem root" do
    around do |example|
      skip "filesystem root semantics are Unix-only" if Gem.win_platform?

      previous_root = SimpleCov.root
      SimpleCov.root("/")
      example.run
    ensure
      SimpleCov.root(previous_root)
    end

    let(:result_set) do
      {
        "/test/server/foo_test.rb" => {"lines" => [1]},
        "/app/src/foo.rb" => {"lines" => [1]}
      }
    end

    it "retains every absolute path instead of dropping them all" do
      expect(remover.keys).to contain_exactly("/test/server/foo_test.rb", "/app/src/foo.rb")
    end
  end

  describe ".root_regex" do
    around do |example|
      previous = SimpleCov.root
      example.run
    ensure
      SimpleCov.root previous
    end

    it "rebuilds the pattern when the root changes" do
      one = File.expand_path("/one")
      two = File.expand_path("/two")

      SimpleCov.root one
      first = described_class.root_regex
      expect(first.match?("#{one}/lib/a.rb")).to be(true)

      SimpleCov.root two
      rebuilt = described_class.root_regex
      expect(rebuilt).not_to be(first)
      expect(rebuilt.match?("#{two}/lib/a.rb")).to be(true)
      expect(rebuilt.match?("#{one}/lib/a.rb")).to be(false)
    end

    it "answers the same pattern while the root stands still" do
      described_class.instance_variable_set(:@root_regex_root, nil)
      allow(SimpleCov).to receive(:root) { +"/one" }

      first = described_class.root_regex
      expect(described_class.root_regex).to be(first)
    end

    it "reads a root that looks like a pattern as a path" do
      described_class.instance_variable_set(:@root_regex_root, nil)
      allow(SimpleCov).to receive(:root).and_return("/one+two")

      expect(described_class.root_regex.match?("/one+two/lib/a.rb")).to be(true)
      expect(described_class.root_regex.match?("/oneetwo/lib/a.rb")).to be(false)
    end

    it "matches the root as a directory, not as a prefix" do
      SimpleCov.root "/one"
      expect(described_class.root_regex.match?("/oneother/lib/a.rb")).to be(false)
    end

    it "reads a root that already ends in a separator" do
      described_class.instance_variable_set(:@root_regex_root, nil)
      allow(SimpleCov).to receive(:root).and_return("/one/")

      expect(described_class.root_regex.match?("/one/lib/a.rb")).to be(true)
    end

    it "matches a root whose case differs on disk" do
      SimpleCov.root File.expand_path("/One")
      expect(described_class.root_regex.match?("#{File.expand_path("/one")}/lib/a.rb")).to be(true)
    end
  end
end
