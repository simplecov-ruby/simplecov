# frozen_string_literal: true

require "helper"
require "coverage"
require "tempfile"

RSpec.describe SimpleCov::SimulateCoverage do
  describe ".call" do
    let(:fixture) { source_fixture("sample.rb") }

    # TruffleRuby doesn't implement Coverage.line_stub at all, and JRuby's
    # implementation returns the wrong length for multi-line statements.
    # The contexts below assert the exact shape line_stub produces and are
    # gated accordingly.
    has_line_stub = Coverage.respond_to?(:line_stub)
    line_stub_handles_multiline = has_line_stub && RUBY_ENGINE == "ruby"

    it "produces a hash with lines/branches/methods keys" do
      result = described_class.call(fixture)
      expect(result.keys).to contain_exactly("lines", "branches", "methods")
    end

    it "classifies the file's lines as an Array" do
      result = described_class.call(fixture)
      expect(result["lines"]).to be_an(Array)
      expect(result["lines"]).not_to be_empty
    end

    # Pre-#1059 behavior was to leave branches/methods empty, so unloaded
    # files were invisible to those denominators while their lines DID
    # count. SimulateCoverage now enumerates branches and methods via
    # StaticCoverageExtractor so the totals stay symmetric. On Rubies
    # without Prism the static path no-ops and the fields stay empty —
    # both shapes are documented as valid here.
    it "returns hash-shaped branches and methods" do
      result = described_class.call(fixture)
      expect(result["branches"]).to be_a(Hash)
      expect(result["methods"]).to be_a(Hash)
    end

    context "when Prism is available" do
      it "synthesizes branch entries for unloaded files",
         if: SimpleCov::StaticCoverageExtractor.available? do
        with_tmp_source("def f(x)\n  x > 0 ? :y : :n\nend\n") do |path|
          result = described_class.call(path)
          expect(result["branches"]).not_to be_empty
          types = result["branches"].keys.map(&:first)
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

    # Regression for https://github.com/simplecov-ruby/simplecov/issues/654.
    # A multi-line statement (method chain, hash literal, etc.) used to count
    # every continuation line as relevant when the file was tracked but not
    # loaded — even though Ruby's Coverage module marks the continuations as
    # nil for a loaded file. The two paths now agree.
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
          # Coverage.line_stub is what Ruby would have produced if the file
          # were required — the def + first assignment line are relevant,
          # the chained calls and `end` are not.
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil])
        end
      end
    end

    # Coverage.line_stub doesn't understand SimpleCov's `# :nocov:` toggles,
    # so the overlay step must demote those lines to nil.
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
          # `def shown` + `1` + `end` for the visible method are relevant;
          # everything from the opening :nocov: through the closing one is nil.
          expect(described_class.call(path)["lines"]).to eq([0, 0, nil, nil, nil, nil, nil, nil])
        end
      end
    end

    # Same overlay path, but with the new `# simplecov:disable line` directive.
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
        # With the fallback, every non-blank/non-comment line is relevant —
        # the historical (pre-#654) behavior.
        with_tmp_source("a = 1\nb = 2\n") do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0])
        end
      end
    end

    # Simulates JRuby / TruffleRuby, where Coverage.line_stub doesn't exist.
    # Runs on every engine so the fallback branch stays exercised on MRI.
    context "when Coverage doesn't expose line_stub" do
      it "falls back to LinesClassifier's raw output" do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:line_stub).and_return(false)
        with_tmp_source("a = 1\nb = 2\n") do |path|
          expect(described_class.call(path)["lines"]).to eq([0, 0])
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
