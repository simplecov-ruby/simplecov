# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::ResultAdapter do
  subject(:adapter) { described_class.call(result_set) }

  let(:existing_file) { source_fixture("app/models/user.rb") }

  describe "with oneshot_lines coverage" do
    context "when all tracked files exist" do
      let(:result_set) do
        {
          existing_file => {oneshot_lines: [2, 3, 4]}
        }
      end

      it "adapts the coverage data to an array" do
        expect(adapter[existing_file][:lines]).to be_an(Array)
      end

      it "marks every oneshot line as hit once" do
        expect(adapter[existing_file][:lines].values_at(1, 2, 3)).to eq([1, 1, 1])
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
        expect(adapter[deleted_file][:lines]).to eq([1, nil, 1])
      end

      it "still adapts the existing file normally" do
        expect(adapter[existing_file][:lines].values_at(1, 2)).to eq([1, 1])
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
        expect(adapter[non_ruby_file][:lines]).to eq([1])
      end

      it "still adapts the existing file normally" do
        expect(adapter[existing_file][:lines][1]).to eq(1)
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
    def named_shadowing_module
      mod = Module.new do
        def inspect(value, _max_depth = 2)
          value.to_s
        end
        module_function :inspect
      end
      stub_const("FakeLiquidUtils", mod)
      mod
    end

    def anonymous_shadowing_module
      Module.new do
        def inspect(value)
          value
        end
        module_function :inspect
      end
    end

    def broken_to_s_module
      Module.new do
        def self.to_s
          raise ArgumentError, "broken to_s"
        end
      end
    end

    def broken_inspect_instance
      Class.new do
        def inspect(_depth)
          "unreachable"
        end
      end.new
    end

    def constant_nested_module
      inner = Module.new
      Class.new.const_set(:Inner, inner)
      inner
    end

    it "keeps an address out of the named singleton wrapper" do
      expect(rendered_receiver_for(named_shadowing_module.singleton_class)).not_to match(/0x\h{2,}/)
    end

    it "recovers the named singleton wrapper via Module#name" do
      expect(rendered_receiver_for(named_shadowing_module.singleton_class)).to eq("FakeLiquidUtils") if RUBY_ENGINE == "ruby"
    end

    it "keeps an address out of an anonymous shadowing module" do
      expect(rendered_receiver_for(anonymous_shadowing_module.singleton_class)).not_to match(/0x\h{2,}/)
    end

    it "falls back to the address form for an anonymous shadowing module" do
      expect(rendered_receiver_for(anonymous_shadowing_module.singleton_class)).to eq("#<Class:0x0>") if RUBY_ENGINE == "ruby"
    end

    it "falls back to the address form when to_s itself is shadowed" do
      expect(rendered_receiver_for(broken_to_s_module)).to eq("#<Module:0x0>")
    end

    it "renders an instance's singleton class without invoking its inspect" do
      expect(rendered_receiver_for(broken_inspect_instance.singleton_class)).to eq("#<Class:#<#<Class:0x0>:0x0>>")
    end

    it "renders a receiver that is not a module at all" do
      expect(rendered_receiver_for(breaking_to_s(Object.new))).to eq("#<Object:0x0>")
    end

    it "renders a class that is not a singleton class" do
      expect(rendered_receiver_for(breaking_to_s(Class.new))).to eq("#<Class:0x0>")
    end

    it "recovers a named class's singleton wrapper via Module#name" do
      klass = Class.new
      stub_const("FakeNamedClass", klass)
      expect(rendered_receiver_for(breaking_to_s(klass.singleton_class))).to eq("FakeNamedClass")
    end

    it "keeps an address out of a wrapper whose attached object is not a module" do
      expect(rendered_receiver_for(breaking_to_s(Object.new.singleton_class))).not_to match(/0x\h{2,}/)
    end

    it "falls back to the address form when the attached object is not a module" do
      expect(rendered_receiver_for(breaking_to_s(Object.new.singleton_class))).to eq("#<Class:0x0>") if RUBY_ENGINE == "ruby"
    end

    it "keeps an address out of a name that is not a constant path" do
      expect(rendered_receiver_for(breaking_to_s(constant_nested_module.singleton_class))).not_to match(/0x\h{2,}/)
    end

    it "keeps the wrapper around a name that is not a constant path" do
      expect(rendered_receiver_for(breaking_to_s(constant_nested_module.singleton_class))).to eq("#<Class:#<Class:0x0>::Inner>") if RUBY_ENGINE == "ruby"
    end

    def breaking_to_s(receiver)
      receiver.singleton_class.define_method(:to_s) { raise ArgumentError, "broken to_s" }
      receiver
    end

    def adapter_for(receiver)
      result = described_class.call(
        existing_file => {methods: {[receiver, :helper, 5, 2, 5, 12] => 1}}
      )
      result[existing_file][:methods]
    end

    def rendered_receiver_for(receiver)
      adapter_for(receiver).keys.first[0]
    end
  end

  describe "method coverage key normalization" do
    let(:adapted_methods) { adapter[existing_file][:methods] }

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
      expect(adapted_methods.keys.first[0]).to eq("#<Class:0x0>")
    end

    context "with a 32-bit-style 8-char address" do
      let(:result_set) do
        {existing_file => {methods: {["#<Class:0xabcdef01>", :bar, 1, 0, 2, 2] => 1}}}
      end

      it "still normalizes the address" do
        expect(adapted_methods.keys.first[0]).to eq("#<Class:0x0>")
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

      it "merges singleton and instance entries into a single key" do
        expect(adapted_methods.keys.size).to eq(1)
      end

      it "keeps the instance form's name on the merged key" do
        expect(adapted_methods.keys.first[0]).to eq("SimpleCov::Combine")
      end

      it "combines the hits of both entries" do
        expect(adapted_methods.values.first).to eq(5)
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

      it "normalizes them down to a single key" do
        expect(adapted_methods.keys.size).to eq(1)
      end

      it "merges their hit counts after normalization" do
        expect(adapted_methods.values.first).to eq(7)
      end
    end

    context "with the same define_method block defined on differently-shaped receivers" do
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
        expect(adapted_methods).to eq(["#<Class:#<Class:0x0>>", :method_added, 18, 55, 22, 9] => 6)
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
        expect(adapted_methods.values).to eq([1])
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
        expect(adapted_methods.keys.size).to eq(2)
      end

      it "keeps each location's hits with it" do
        expect(adapted_methods.values).to contain_exactly(1, 0)
      end
    end

    context "with locations that differ only in their start line" do
      let(:result_set) do
        {
          existing_file => {
            methods: {
              ["Foo", :outer, 2, 4, 9, 7] => 1,
              ["Foo", :inner, 5, 4, 9, 7] => 0
            }
          }
        }
      end

      it "keeps them separate" do
        expect(adapted_methods.keys.size).to eq(2)
      end

      it "keeps each start line's hits with it" do
        expect(adapted_methods.values).to contain_exactly(1, 0)
      end
    end

    context "with one define_method block generating many method names" do
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

      it "collapses all generated names into one key" do
        expect(adapted_methods.keys.size).to eq(1)
      end

      it "aggregates all generated names at the block's location" do
        expect(adapted_methods.values).to eq([1])
      end
    end
  end

  describe "eval-duplicated branch aggregation" do
    let(:adapted_branches) { adapter[existing_file][:branches] }

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

    it "aggregates duplicated conditions by location" do
      expect(adapted_branches.keys.size).to eq(2)
    end

    it "sums the arm hits of the duplicated condition" do
      expect(adapted_branches[[:if, 0, 3, 3, 19, 6]].values).to contain_exactly(1, 2)
    end

    it "leaves distinct conditions untouched" do
      expect(adapted_branches[[:if, 18, 30, 3, 32, 6]].values).to eq([4, 0])
    end

    it "ignores entries without branch data" do
      expect(described_class.call({existing_file => {lines: [nil, 1]}})[existing_file]).not_to have_key(:branches)
    end
  end
end
