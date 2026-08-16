# frozen_string_literal: true

require "helper"
require "simplecov/test_contexts/test_table"

RSpec.describe SimpleCov::TestContexts::TestTable do
  subject(:table) { described_class.new }

  it "assigns indices in interning order" do
    expect(table.intern("a", "test a")).to eq 0
    expect(table.intern("b", "test b")).to eq 1
    expect(table.entries).to eq [["a", "test a"], ["b", "test b"]]
  end

  it "returns the existing index for an already interned id" do
    table.intern("a", "test a")
    table.intern("b", "test b")

    expect(table.intern("a", "test a")).to eq 0
    expect(table.entries.size).to eq 2
  end

  it "keeps the first-seen name for an id" do
    table.intern("a", "first name")
    table.intern("a", "second name")

    expect(table.entries).to eq [["a", "first name"]]
  end

  it "defaults the name to the id" do
    table.intern("FooTest#test_bar")

    expect(table.entries).to eq [["FooTest#test_bar", "FooTest#test_bar"]]
  end

  it "starts empty" do
    expect(table.entries).to be_empty
  end
end
