# frozen_string_literal: true

require "helper"
require "coverage"
require "tempfile"
require "tmpdir"

RSpec.describe SimpleCov::SimulateCoverage do
  describe ".call" do
    let(:fixture) { source_fixture("sample.rb") }

    it "produces a hash with lines/branches/methods keys" do
      result = described_class.call(fixture)
      expect(result.keys).to contain_exactly("lines", "branches", "methods")
    end

    # A track_files glob can sweep up entries that exist but can't be
    # read as files (a directory named like a Ruby file, permission
    # denied). Rescuing only ENOENT crashed the merge or report step on
    # those; they must degrade to "empty file" like a missing one.
    it "treats an unreadable path as an empty file" do
      Dir.mktmpdir("simulate-coverage-spec-") do |dir|
        result = described_class.call(dir)
        expect(result["lines"]).to eq([])
        expect(result["branches"]).to eq({})
      end
    end

    it "classifies the file's lines as an Array" do
      result = described_class.call(fixture)
      expect(result["lines"]).to be_an(Array)
      expect(result["lines"]).not_to be_empty
    end

    # Pre-#1059 behavior was to leave branches/methods empty, so unloaded
    # files were invisible to those denominators while their lines DID
    # count. SimulateCoverage now enumerates branches and methods via
    # StaticCoverageExtractor so the totals stay symmetric.
    it "returns hash-shaped branches and methods" do
      result = described_class.call(fixture)
      expect(result["branches"]).to be_a(Hash)
      expect(result["methods"]).to be_a(Hash)
    end

    it "synthesizes branch entries for unloaded files" do
      with_tmp_source("def f(x)\n  x > 0 ? :y : :n\nend\n") do |path|
        result = described_class.call(path)
        expect(result["branches"]).not_to be_empty
        types = result["branches"].keys.map(&:first)
        expect(types).to include(:if)
      end
    end

    it "synthesizes method entries for unloaded files" do
      with_tmp_source("class Foo\n  def bar; end\nend\n") do |path|
        result = described_class.call(path)
        method_names = result["methods"].keys.map { |k| k[1] }
        expect(method_names).to include(:bar)
      end
    end

    # Regression for https://github.com/simplecov-ruby/simplecov/issues/654.
    # A multi-line statement (method chain, hash literal, etc.) used to count
    # every continuation line as relevant when the file was tracked but not
    # loaded — even though Ruby's Coverage module marks the continuations as
    # nil for a loaded file. The two paths now agree.
    context "with a multi-line method chain" do
      let(:source) { <<~RUBY }
        def show
          @product = base_scope
                     .includes(colors_products: :color)
                     .find(params[:id])
        end
      RUBY

      it "returns the same line classification Coverage produces for a loaded file" do
        with_tmp_source(source) do |path|
          # Coverage.line_stub is what Ruby would have produced if the file
          # were required — the def + first assignment line are relevant,
          # the chained calls and `end` are not.
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil])
        end
      end
    end

    # Coverage.line_stub doesn't understand SimpleCov's `# :nocov:` toggles,
    # so the overlay step must demote those lines to nil.
    context "with a :nocov: block" do
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
          # `def shown` + `1` + `end` for the visible method are relevant;
          # everything from the opening :nocov: through the closing one is nil.
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil, nil, nil, nil])
        end
      end
    end

    # Same overlay path, but with the new `# simplecov:disable line` directive.
    context "with a simplecov:disable line range" do
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
        # With the fallback, every non-blank/non-comment line is relevant —
        # the historical (pre-#654) behavior.
        with_tmp_source("a = 1\nb = 2\n") do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0])
        end
      end
    end

    # The caller passes `synthesize: false` when neither branch nor method
    # coverage is enabled, since nothing reads the tuples and the Prism parse
    # that produces them is about half the cost of simulating a file. See #1250.
    context "with synthesize: false" do
      let(:source) { "def f(x)\n  x > 0 ? :y : :n\nend\n" }

      it "returns empty branches and methods" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path)["branches"]).not_to be_empty

          skipped = described_class.call(path, synthesize: false)
          expect(skipped["branches"]).to be_empty
          expect(skipped["methods"]).to be_empty
        end
      end

      it "classifies lines exactly as it does with synthesis on" do
        with_tmp_source(source) do |path|
          expect(described_class.call(path, synthesize: false)["lines"])
            .to eq(described_class.call(path)["lines"])
        end
      end

      # Empty tuples alone would also be satisfied by parsing and discarding
      # the result. The point of the flag is that the Prism parse — over half
      # the cost of simulating a file — never happens.
      it "does not parse the file at all" do
        with_tmp_source(source) do |path|
          allow(SimpleCov::StaticCoverageExtractor).to receive(:call).and_call_original

          described_class.call(path, synthesize: false)

          expect(SimpleCov::StaticCoverageExtractor).not_to have_received(:call)
        end
      end
    end

    # `Coverage.result` reports no lines for a file loaded under a branch-only
    # or method-only run, so a simulated file must not report them either.
    # Zeroed lines would make it indistinguishable from a file a sibling
    # process actually loaded once the two are merged. See #1250.
    context "with lines: false" do
      it "omits the lines key entirely" do
        with_tmp_source("def f(x)\n  x\nend\n") do |path|
          result = described_class.call(path, lines: false)
          expect(result).not_to have_key("lines")
          expect(result.keys).to contain_exactly("branches", "methods")
        end
      end

      it "still synthesizes branches and methods" do
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
end
