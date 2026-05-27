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

  it "keeps the legacy root_regx helper as an alias" do
    expect(described_class.root_regx).to eq(described_class.root_regex)
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
end
