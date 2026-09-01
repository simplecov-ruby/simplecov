# frozen_string_literal: true

require "helper"
require "coverage"
require "tempfile"
require "tmpdir"

RSpec.describe SimpleCov::SimulateCoverage do
  describe ".call" do
    let(:fixture) { source_fixture("sample.rb") }

    has_line_stub = Coverage.respond_to?(:line_stub)
    line_stub_handles_multiline = has_line_stub && RUBY_ENGINE == "ruby"

    it "produces a hash with lines/branches/methods keys" do
      result = described_class.call(fixture)
      expect(result.keys).to contain_exactly("lines", "branches", "methods")
    end

    it "treats an unreadable path as a file with no lines" do
      Dir.mktmpdir("simulate-coverage-spec-") do |dir|
        expect(described_class.call(dir)["lines"]).to eq([])
      end
    end

    it "treats an unreadable path as a file with no branches" do
      Dir.mktmpdir("simulate-coverage-spec-") do |dir|
        expect(described_class.call(dir)["branches"]).to eq({})
      end
    end

    it "classifies the file's lines as an Array" do
      expect(described_class.call(fixture)["lines"]).to be_an(Array)
    end

    it "classifies at least one of the file's lines" do
      expect(described_class.call(fixture)["lines"]).not_to be_empty
    end

    it "returns hash-shaped branches" do
      expect(described_class.call(fixture)["branches"]).to be_a(Hash)
    end

    it "returns hash-shaped methods" do
      expect(described_class.call(fixture)["methods"]).to be_a(Hash)
    end

    context "when Prism is available" do
      let(:ternary_source) { "def f(x)\n  x > 0 ? :y : :n\nend\n" }

      it "synthesizes branch entries for unloaded files",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(ternary_source) do |path|
          expect(described_class.call(path)["branches"]).not_to be_empty
        end
      end

      it "names the type of the branch it synthesized",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(ternary_source) do |path|
          types = described_class.call(path)["branches"].keys.map(&:first)
          expect(types).to include(:if)
        end
      end

      it "synthesizes method entries for unloaded files",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source("class Foo\n  def bar; end\nend\n") do |path|
          result = described_class.call(path)
          method_names = result["methods"].keys.map { |k| k[1] }
          expect(method_names).to include(:bar)
        end
      end
    end

    context "with a multi-line method chain", if: line_stub_handles_multiline do
      let(:source) { <<~RUBY }
        def show
          @product = base_scope
                     .includes(colors_products: :color)
                     .find(params[:id])
        end
      RUBY

      it "returns the same line classification Coverage produces for a loaded file" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil])
        end
      end
    end

    context "with a :nocov: block", if: has_line_stub do
      let(:source) { <<~RUBY }
        def shown
          1
        end
        # :nocov:
        def hidden
          2
        end
        # :nocov:
      RUBY

      it "demotes the :nocov: lines (and the toggles themselves) to nil" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil, nil, nil, nil])
        end
      end
    end

    context "with a simplecov:disable line range", if: has_line_stub do
      let(:source) { <<~RUBY }
        def shown
          1
        end
        # simplecov:disable line
        def hidden
          2
        end
        # simplecov:enable line
      RUBY

      it "demotes the disabled range to nil" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil, nil, nil, nil])
        end
      end
    end

    context "when the file does not exist" do
      it "returns the empty-shape hash without raising" do
        expect(described_class.call("/no/such/file.rb"))
          .to eq("lines" => [], "branches" => {}, "methods" => {})
      end
    end

    context "when Coverage.line_stub raises SyntaxError" do
      it "falls back to LinesClassifier's raw output" do
        allow(Coverage).to receive(:line_stub).and_raise(SyntaxError, "boom")
        with_tmp_source("a = 1\nb = 2\n") do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0])
        end
      end
    end

    context "when Coverage doesn't expose line_stub" do
      it "falls back to LinesClassifier's raw output" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:line_stub).and_return(false)
        with_tmp_source("a = 1\nb = 2\n") do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0])
        end
      end
    end

    context "with synthesize: false" do
      let(:source) { "def f(x)\n  x > 0 ? :y : :n\nend\n" }

      it "has branches to skip in the first place",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(source) do |path|
          expect(described_class.call(path)["branches"]).not_to be_empty
        end
      end

      it "returns empty branches",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(source) do |path|
          expect(described_class.call(path, synthesize: false)["branches"]).to be_empty
        end
      end

      it "returns empty methods",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(source) do |path|
          expect(described_class.call(path, synthesize: false)["methods"]).to be_empty
        end
      end

      it "classifies lines exactly as it does with synthesis on" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path, synthesize: false)["lines"])
            .to eq(described_class.call(path)["lines"])
        end
      end

      it "does not parse the file at all",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source(source) do |path|
          allow(SimpleCov::StaticCoverageExtractor).to receive(:call).and_call_original

          described_class.call(path, synthesize: false)

          expect(SimpleCov::StaticCoverageExtractor).not_to have_received(:call)
        end
      end
    end

    context "with lines: false" do
      it "omits the lines key entirely" do
        with_tmp_source("def f(x)\n  x\nend\n") do |path|
          expect(described_class.call(path, lines: false)).not_to have_key("lines")
        end
      end

      it "carries the branches and methods keys, and nothing besides" do
        with_tmp_source("def f(x)\n  x\nend\n") do |path|
          expect(described_class.call(path, lines: false).keys).to contain_exactly("branches", "methods")
        end
      end

      it "still synthesizes branches and methods",
        if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source("def f(x)\n  x > 0 ? :y : :n\nend\n") do |path|
          expect(described_class.call(path, lines: false)["branches"]).not_to be_empty
        end
      end
    end

    def with_tmp_source(content)
      Tempfile.create(["sc654", ".rb"]) do |f|
        f.write(content)
        f.close
        yield f.path
      end
    end
  end

  it "synthesizes no lines where Coverage cannot stub them" do
    allow(Coverage).to receive(:respond_to?).and_call_original
    allow(Coverage).to receive(:respond_to?).with(:line_stub).and_return(false)

    expect(described_class.send(:coverage_stub, __FILE__, ["a = 1\n"])).to be_nil
  end

  it "carries the branch and method tuples, and nothing besides" do
    allow(SimpleCov::StaticCoverageExtractor).to receive(:call)
      .and_return("branches" => {b: 1}, "methods" => {m: 2}, "lines" => [1])

    expect(described_class.send(:synthesized_tuples, ["a = 1\n"], true))
      .to eq("branches" => {b: 1}, "methods" => {m: 2})
  end
end
