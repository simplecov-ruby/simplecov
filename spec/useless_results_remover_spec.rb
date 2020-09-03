# frozen_string_literal: true

require "helper"

describe SimpleCov::UselessResultsRemover do
  let(:gem_file_path) { "usr/bin/lib/2.5.0/gems/sample-gem/sample.rb" }
  let(:source_path) { source_fixture("app/models/user.rb") }

  let(:result_set) do
    {
      gem_file_path => {
        lines: [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil],
        branches: {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}},
        methods: {}
      },
      source_path => {
        lines: [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil],
        branches: {[:if, 3, 8, 6, 8, 36] => {[:then, 4, 8, 6, 8, 12] => 47, [:else, 5, 8, 6, 8, 36] => 24}},
        methods: {}
      }
    }
  end

  subject do
    SimpleCov::UselessResultsRemover.call(result_set)
  end

  it "Result ignore gem file path from result set" do
    expect(result_set[gem_file_path]).to be_kind_of(Hash)
    expect(subject).not_to have_key(gem_file_path)
  end

  it "still retains the app path" do
    expect(subject).to have_key(source_path)
    expect(subject[source_path][:lines]).to be_kind_of(Array)
  end
end
