# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::ResultAdapter do
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

  describe "receiver classes whose name rendering executes broken user code" do
    # A singleton class's `to_s` renders its attached object via `#inspect`,
    # which user code can shadow with an incompatible signature — Liquid's
    # `Utils.inspect(value, max_depth = 2)` module_function is the wild
    # example. The report must degrade, not crash the host suite (#1236).
    def named_shadowing_module
      mod = Module.new do
        def inspect(value, max_depth = 2) # rubocop:disable Lint/UnusedMethodArgument
          value.to_s
        end
        module_function :inspect
      end
      stub_const("FakeLiquidUtils", mod)
      mod
    end

    it "recovers the named singleton wrapper via Module#name" do
      methods = adapter_for(named_shadowing_module.singleton_class)
      expect(methods.keys.first[0]).to eq("FakeLiquidUtils")
    end

    it "falls back to the address form for an anonymous shadowing module" do
      mod = Module.new do
        def inspect(value)
          value
        end
        module_function :inspect
      end
      methods = adapter_for(mod.singleton_class)
      expect(methods.keys.first[0]).to eq("#<Class:0x0>")
    end

    it "falls back to the address form when to_s itself is shadowed" do
      mod = Module.new do
        def self.to_s
          raise ArgumentError, "broken to_s"
        end
      end
      methods = adapter_for(mod)
      expect(methods.keys.first[0]).to eq("#<Module:0x0>")
    end

    it "renders an instance's singleton class without invoking its inspect" do
      # `def some_object.helper` records the object's singleton class. CRuby
      # renders those from the class name chain without calling the object's
      # #inspect, so even a broken inspect can't interfere; the nested
      # addresses still normalize.
      broken = Class.new do
        def inspect(_depth)
          "unreachable"
        end
      end.new
      methods = adapter_for(broken.singleton_class)
      expect(methods.keys.first[0]).to eq("#<Class:#<#<Class:0x0>:0x0>>")
    end

    def adapter_for(receiver)
      result = described_class.call(
        existing_file => {methods: {[receiver, :helper, 5, 2, 5, 12] => 1}}
      )
      result[existing_file][:methods]
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

    context "with module_function double-counting (singleton + instance forms)" do
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["#<Class:SimpleCov::Combine>", :combine, 16, 4, 20, 7] => 5,
              [SimpleCov::Combine, :combine, 16, 4, 20, 7] => 0
            }
          }
        }
      end

      it "merges singleton and instance entries into a single key with combined hits" do
        methods = adapter[existing_file][:methods]
        expect(methods.keys.size).to eq(1)
        expect(methods.keys.first[0]).to eq("SimpleCov::Combine")
        expect(methods.values.first).to eq(5)
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

    context "with the same define_method block defined on differently-shaped receivers" do
      # One `define_singleton_method :method_added` block, defined onto a
      # Class descendant (called 6 times) and a Module descendant (never
      # called — e.g. a spec exercising a type-check failure path). Ruby
      # records one entry per receiver; the receiver shapes normalize
      # differently, so without location aggregation the Module copy is a
      # phantom uncovered method on a fully-covered line (issue #1234).
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["#<Class:#<Class:0x00007f0000000001>>", :method_added, 18, 55, 22, 9] => 6,
              ["#<Class:#<Module:0x00007f0000000002>>", :method_added, 18, 55, 22, 9] => 0
            }
          }
        }
      end

      it "aggregates per-receiver entries at the same source location" do
        methods = adapter[existing_file][:methods]
        expect(methods).to eq(["#<Class:#<Class:0x0>>", :method_added, 18, 55, 22, 9] => 6)
      end
    end

    context "with a named and an anonymous receiver sharing a location" do
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["SomeNamedClass", :inspect, 3, 39, 3, 51] => 0,
              ["#<Class:0x00007f0000000003>", :inspect, 3, 39, 3, 51] => 1
            }
          }
        }
      end

      it "sums hits so the covered receiver wins" do
        methods = adapter[existing_file][:methods]
        expect(methods.values).to eq([1])
      end
    end

    context "with same-named methods at different locations" do
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["Foo", :call, 2, 2, 4, 5] => 1,
              ["Bar", :call, 8, 2, 10, 5] => 0
            }
          }
        }
      end

      it "keeps them separate (distinct source methods)" do
        methods = adapter[existing_file][:methods]
        expect(methods.keys.size).to eq(2)
        expect(methods.values).to contain_exactly(1, 0)
      end
    end

    context "with one define_method block generating many method names" do
      # A builder looping `container.each_key { |key| define_method(key) { ... } }`
      # produces one entry per generated name, all at the block's location.
      # Only some generated wrappers get called, but the source location
      # executed, which is all a file-based report can express (#1234).
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["#<Builder:0x00007f0000000001>", :echo, 38, 26, 41, 11] => 1,
              ["#<Builder:0x00007f0000000001>", :bind, 38, 26, 41, 11] => 0,
              ["#<Builder:0x00007f0000000001>", :check, 38, 26, 41, 11] => 0
            }
          }
        }
      end

      it "aggregates all generated names at the block's location" do
        methods = adapter[existing_file][:methods]
        expect(methods.keys.size).to eq(1)
        expect(methods.values).to eq([1])
      end
    end
  end

  describe "eval-duplicated branch aggregation" do
    # Ruby's eval coverage emits a fresh set of branch entries per COMPILE
    # of a template (hanami-view compiles the same .erb once per view), so
    # one source `if` shows up as several conditions at identical
    # coordinates, each seeing only its own renders. Reported separately
    # they inflate the denominator and turn a side covered under another
    # compile into a phantom miss (issue #1235).
    let(:result_set) do
      {
        existing_file => {
          branches: {
            [:if, 0, 3, 3, 19, 6] => {[:then, 1, 4, 4, 4, 10] => 1, [:else, 2, 3, 3, 19, 6] => 0},
            [:if, 9, 3, 3, 19, 6] => {[:then, 10, 4, 4, 4, 10] => 0, [:else, 11, 3, 3, 19, 6] => 2},
            [:if, 18, 30, 3, 32, 6] => {[:then, 19, 31, 4, 31, 10] => 4, [:else, 20, 30, 3, 32, 6] => 0}
          }
        }
      }
    end

    it "aggregates duplicated conditions by location, summing arm hits" do
      branches = adapter[existing_file][:branches]
      expect(branches.keys.size).to eq(2)

      duplicated = branches[[:if, 0, 3, 3, 19, 6]]
      expect(duplicated.values).to contain_exactly(1, 2)
    end

    it "leaves distinct conditions untouched" do
      branches = adapter[existing_file][:branches]
      expect(branches[[:if, 18, 30, 3, 32, 6]].values).to eq([4, 0])
    end

    it "ignores entries without branch data" do
      expect(described_class.call({existing_file => {lines: [nil, 1]}})[existing_file]).not_to have_key(:branches)
    end
  end
end
