# frozen_string_literal: true

require "helper"
require "coverage"

describe SimpleCov::ResultAdapter do
  subject(:adapter) { described_class.call(result_set) }

  let(:existing_file) { source_fixture("app/models/user.rb") }

  describe "with oneshot_lines coverage" do
    before do
      skip "oneshot_lines coverage not supported on truffleruby" if RUBY_ENGINE == "truffleruby"
    end

    context "when all tracked files exist" do
      let(:result_set) do
        {
          existing_file => {oneshot_lines: [2, 3, 4]}
        }
      end

      it "adapts the coverage data to lines format" do
        lines = adapter[existing_file][:lines]
        expect(lines).to be_an(Array)
        expect(lines[1]).to eq(1)
        expect(lines[2]).to eq(1)
        expect(lines[3]).to eq(1)
      end
    end

    context "when a tracked file no longer exists on disk" do
      let(:deleted_file) { File.join(SimpleCov.root, "lib/deleted_generated_file.rb") }

      let(:result_set) do
        {
          existing_file => {oneshot_lines: [2, 3]},
          deleted_file => {oneshot_lines: [1, 3]}
        }
      end

      it "builds a fallback line stub for the missing file" do
        lines = adapter[deleted_file][:lines]
        expect(lines[0]).to eq(1)
        expect(lines[2]).to eq(1)
      end

      it "still adapts the existing file normally" do
        lines = adapter[existing_file][:lines]
        expect(lines[1]).to eq(1)
        expect(lines[2]).to eq(1)
      end
    end

    context "when a tracked file is not valid Ruby" do
      let(:non_ruby_file) { source_fixture("non_ruby_config.yml") }
      let(:result_set) do
        {
          existing_file => {oneshot_lines: [2]},
          non_ruby_file => {oneshot_lines: [1]}
        }
      end

      before do
        File.write(non_ruby_file, "development: &default\n  adapter: mysql2\n")
      end

      after do
        FileUtils.rm_f(non_ruby_file)
      end

      it "builds a fallback line stub for the non-parseable file" do
        lines = adapter[non_ruby_file][:lines]
        expect(lines[0]).to eq(1)
      end

      it "still adapts the existing file normally" do
        lines = adapter[existing_file][:lines]
        expect(lines[1]).to eq(1)
      end
    end
  end

  describe ".call with no result" do
    it "returns nil when handed a nil result" do
      expect(described_class.call(nil)).to be_nil
    end
  end

  describe ".call with an Array-shaped pre-0.18 cover_statistic" do
    it "wraps the array as the lines key" do
      legacy = {"/abs/foo.rb" => [nil, 1, 1, 0]}
      expect(described_class.call(legacy)).to eq("/abs/foo.rb" => {"lines" => [nil, 1, 1, 0]})
    end
  end

  describe "method coverage key normalization" do
    let(:result_set) do
      {
        existing_file => {
          methods: {
            ["#<Class:0x00007ff19ab24790>", :foo, 1, 0, 3, 3] => 2,
            ["#<Class:0x00007ff19ab24790>", :foo, 1, 0, 3, 3] => 3 # rubocop:disable Lint/DuplicateHashKey
          }
        }
      }
    end

    it "collapses 64-bit hex addresses to a stable placeholder" do
      methods = adapter[existing_file][:methods]
      key = methods.keys.first
      expect(key[0]).to eq("#<Class:0x0>")
    end

    context "with a 32-bit-style 8-char address" do
      let(:result_set) do
        {existing_file => {methods: {["#<Class:0xabcdef01>", :bar, 1, 0, 2, 2] => 1}}}
      end

      it "still normalizes the address" do
        key = adapter[existing_file][:methods].keys.first
        expect(key[0]).to eq("#<Class:0x0>")
      end
    end

    context "with two distinct anonymous classes that share a method" do
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["#<Class:0x00007ff100000001>", :foo, 1, 0, 3, 3] => 2,
              ["#<Class:0x00007ff100000002>", :foo, 1, 0, 3, 3] => 5
            }
          }
        }
      end

      it "merges their hit counts after normalization" do
        methods = adapter[existing_file][:methods]
        expect(methods.keys.size).to eq(1)
        expect(methods.values.first).to eq(7)
      end
    end
  end
end
