# frozen_string_literal: true

require "helper"
require "fileutils"
require "json"
require "support/coverage_fixtures"

RSpec.describe SimpleCov::Formatter::HTMLFormatter do
  subject(:formatter) { described_class.new(silent: true) }

  let(:loud_formatter) { described_class.new(silent: false) }
  let(:coverage_dir)   { SimpleCov.coverage_dir }
  let(:fixtures_path)  { File.join(source_fixture_base_directory, "fixtures") }

  before do
    FileUtils.rm_rf(coverage_dir)
    FileUtils.mkdir_p(coverage_dir)
    SimpleCov::SourceFile::SkipChunks.nocov_warned.clear
  end

  def fixture_path(name)
    File.join(fixtures_path, name)
  end

  def make_result(coverage = {"sample.rb" => CoverageFixtures::SAMPLE_RB})
    SimpleCov::Result.new(coverage.transform_keys { |name| fixture_path(name) })
  end

  # Extract the embedded coverage JSON back out of the single-file
  # report. The payload's `<` characters are escaped, so the first
  # "</script>" after the assignment is reliably the element's close.
  def embedded_json(dir = coverage_dir)
    html = File.read(File.join(dir, "index.html"))
    html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
  end

  def coverage_data(dir = coverage_dir)
    JSON.parse(embedded_json(dir))
  end

  describe "DATA_MARKER" do
    it "is present exactly once in the compiled template" do
      template = File.read(File.join(formatter.send(:public_dir), "index.html"))
      expect(template.scan(described_class::DATA_MARKER).count).to eq 1
    end
  end

  describe "#format under a non-UTF-8 default external encoding" do
    # A minimal CI container's locale resolves `Encoding.default_external`
    # to US-ASCII (Windows to a code page). The template and payload are
    # read and built as UTF-8 explicitly, so embedding non-ASCII source
    # like utf-8.rb's "135°C" must not raise Encoding::CompatibilityError.
    it "still renders the report" do
      with_default_external(Encoding::US_ASCII) do
        formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))
      end

      expect(embedded_json).to include("135°C")
    end

    it "still renders from a coverage.json carrying non-ASCII source" do
      # `File.read` without an explicit encoding tags the JSON with the
      # locale's encoding, and parsing "135°C" as US-ASCII raises
      # Encoding::InvalidByteSequenceError before the template is even
      # touched.
      formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))

      Dir.mktmpdir do |dir|
        with_default_external(Encoding::US_ASCII) do
          formatter.format_from_json(File.join(coverage_dir, "coverage.json"), dir)
        end

        expect(embedded_json(dir)).to include("135°C")
      end
    end

    def with_default_external(encoding)
      original = Encoding.default_external
      assign_default_external(encoding)
      yield
    ensure
      assign_default_external(original)
    end

    def assign_default_external(encoding)
      verbose = $VERBOSE
      $VERBOSE = nil # assigning default_external warns; that's the point here
      Encoding.default_external = encoding
    ensure
      $VERBOSE = verbose
    end
  end

  describe "#format with output_dir" do
    it "writes index.html into the explicit directory, not SimpleCov.coverage_path" do
      Dir.mktmpdir do |dir|
        described_class.new(silent: true, output_dir: dir).format(make_result)
        expect(File.exist?(File.join(dir, "index.html"))).to be true
        expect(File.exist?(File.join(coverage_dir, "index.html"))).to be false
      end
    end
  end

  describe "#format" do
    before { formatter.format(make_result) }

    it "writes no files besides index.html and coverage.json" do
      expect(Dir.children(coverage_dir).sort).to eq %w[coverage.json index.html]
    end

    it "removes the sibling files a pre-1.0.4 report left behind" do
      # A stale coverage_data.js is worse than clutter: `simplecov serve`
      # would keep serving the old data next to the new report.
      described_class::LEGACY_REPORT_FILES.each { |name| FileUtils.touch(File.join(coverage_dir, name)) }
      FileUtils.touch(File.join(coverage_dir, "unrelated.txt"))

      formatter.format(make_result)

      expect(Dir.children(coverage_dir).sort).to eq %w[coverage.json index.html unrelated.txt]
    end

    # Extraction goes through the `window.SIMPLECOV_DATA = ` marker, so
    # this also pins the embedding shape itself.
    it "embeds parseable JSON in the report" do
      data = coverage_data

      expect(data).to be_a(Hash)
      expect(data).to include("meta", "coverage", "total")
    end

    it "is a self-contained page with the viewer's JS and CSS inlined, not referenced" do
      html = File.read(File.join(coverage_dir, "index.html"))

      expect(html).to include("<!DOCTYPE html>", "<style>", "<script>")
      expect(html).not_to include("src=\"application.js\"", "href=\"application.css\"", "coverage_data.js")
    end

    it "ships no favicon images (the viewer draws one from the live palette)" do
      html = File.read(File.join(coverage_dir, "index.html"))

      expect(html).not_to include("data:image/png", "favicon")
    end

    it "embeds the source code of each file in the coverage payload" do
      file_data = coverage_data["coverage"].values.first

      expect(file_data).to include("source")
      expect(file_data["source"]).to be_a(Array)
      expect(file_data["source"]).not_to be_empty
    end

    it "embeds the metadata section in the coverage payload" do
      meta = coverage_data["meta"]

      expect(meta).to include("simplecov_version", "command_name", "project_name", "timestamp", "root")
      expect(meta["branch_coverage"]).to be(true).or be(false)
      expect(meta["method_coverage"]).to be(true).or be(false)
    end

    # Regression test for #741: in Nix and similar pure-build environments,
    # the gem's static assets ship at mode 0444. Earlier code copied them
    # via `FileUtils.cp_r`, which preserved the read-only mode and then
    # raised EACCES the next run when it tried to open them for writing.
    # The temp-file + rename approach bypasses the open-for-write step.
    it "overwrites read-only assets from prior runs without raising EACCES" do
      formatter.format(make_result)
      Dir[File.join(coverage_dir, "*")].each { |f| File.chmod(0o444, f) }
      expect { formatter.format(make_result) }.not_to raise_error
    end
  end

  describe "#format when source_in_json is false" do
    it "derives coverage.json from one source-bearing payload without mutating it" do
      allow(SimpleCov).to receive(:source_in_json).and_return(false)
      result = make_result
      allow(SimpleCov::Formatter::JSONFormatter).to receive(:build_hash).and_call_original

      formatter.format(result)

      embedded = coverage_data
      external = JSON.parse(File.read(File.join(coverage_dir, "coverage.json")))
      coverage = embedded.fetch("coverage").transform_values { |file| file.except("source") }
      expected = embedded.merge("coverage" => coverage)
      expect(SimpleCov::Formatter::JSONFormatter).to have_received(:build_hash)
        .once.with(result, include_source: true)
      expect(embedded.fetch("coverage").values.first.fetch("source")).not_to be_empty
      expect(external).to eq(expected)
    end
  end

  describe "#render_report escaping" do
    # The coverage JSON lands inside a <script> element, where a raw
    # "</script>" (or "<!--" + "<script") in embedded source text would
    # terminate or destabilize the element. render_report escapes every
    # `<` in the payload, so none of these sequences can occur raw.
    it "keeps embedded </script> and <!-- sequences from breaking the data script element" do
      hostile = {"source" => ["</script><script>alert(1)</script>", "<!-- <script> -->"]}
      html = formatter.send(:render_report, JSON.generate(hostile))
      captured = html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]

      expect(captured).not_to include("<")
      expect(JSON.parse(captured)).to eq hostile
    end

    it "raises a clear error when the template is missing the data marker" do
      allow(File).to receive(:read).and_return("<html></html>")

      expect { formatter.send(:render_report, "{}") }.to raise_error(/marker/)
    end
  end

  describe "#format status" do
    it "emits the HTML report's entry point" do
      stderr = capture_stderr { loud_formatter.format(make_result) }

      expect(stderr.lines.first.chomp).to eq("Coverage report generated for RSpec to tmp/coverage/index.html")
    end
  end

  describe "#format_from_json" do
    let(:standalone_dir) { File.join(coverage_dir, "standalone") }
    let(:json_path) { File.join(coverage_dir, "coverage.json") }

    before { formatter.format(make_result) }

    it "writes a single index.html into the target dir" do
      described_class.new.format_from_json(json_path, standalone_dir)

      expect(Dir.children(standalone_dir)).to eq %w[index.html]
    end

    it "embeds data with the same shape as the in-process format run" do
      described_class.new.format_from_json(json_path, standalone_dir)

      data = coverage_data(standalone_dir)

      expect(data).to include("meta", "coverage")
    end

    it "rejects missing viewer sections before creating the target dir" do
      data = JSON.parse(File.read(json_path))
      File.write(json_path, JSON.dump(data.except("groups")))

      expect { described_class.new.format_from_json(json_path, standalone_dir) }
        .to raise_error(SimpleCov::CoverageJSON::Error, /"groups" must be an object/)
      expect(Dir).not_to exist(standalone_dir)
    end

    it "rejects source-less coverage without replacing an existing report" do
      FileUtils.mkdir_p(standalone_dir)
      index_path = File.join(standalone_dir, "index.html")
      File.write(index_path, "existing report")
      data = JSON.parse(File.read(json_path))
      data.fetch("coverage").each_value { |file| file.delete("source") }
      File.write(json_path, JSON.dump(data))

      expect { described_class.new.format_from_json(json_path, standalone_dir) }
        .to raise_error(SimpleCov::CoverageJSON::Error, /source array.*source_in_json true/)
      expect(File.read(index_path)).to eq("existing report")
    end

    it "rejects coverage entries that are not objects" do
      data = JSON.parse(File.read(json_path))
      filename = data.fetch("coverage").keys.first
      data.fetch("coverage")[filename] = []
      File.write(json_path, JSON.dump(data))

      expect { described_class.new.format_from_json(json_path, standalone_dir) }
        .to raise_error(SimpleCov::CoverageJSON::Error, /coverage entry .* must be an object/)
      expect(Dir).not_to exist(standalone_dir)
    end
  end

  describe "integration with the full ALL_FIXTURES set" do
    let!(:original_criteria) { SimpleCov.coverage_criteria.dup }
    let!(:original_filters)  { SimpleCov.filters.dup }

    let(:full_coverage) { CoverageFixtures::ALL_FIXTURES }

    before do
      SimpleCov.enable_coverage(:branch)
      SimpleCov.filters.clear
      formatter.format(make_result(full_coverage))
    end

    after do
      SimpleCov.clear_coverage_criteria
      original_criteria.each { |criterion| SimpleCov.enable_coverage(criterion) }
      SimpleCov.filters.replace(original_filters)
    end

    it "computes the expected total line-coverage percentage" do
      expect(coverage_data["total"]["lines"]["percent"]).to be_within(0.01).of(75.28)
    end

    it "reports the expected per-file line coverages" do
      pcts = coverage_data["coverage"].values.map { |f| f["lines_covered_percent"] }
      formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

      expect(formatted).to eq %w[
        57.14% 64.28% 66.66% 66.66% 80.00% 85.71%
        85.71% 85.71% 100.00% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes branch totals and per-file branch stats when branch coverage is enabled" do
      skip "Branch coverage not supported on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect(coverage_data["total"]).to have_key("branches")
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("branches", "branches_covered_percent")
      end
    end

    it "reports the expected per-file branch coverages" do
      skip "Branch coverage not supported on this Ruby" unless SimpleCov.branch_coverage_supported?

      pcts = coverage_data["coverage"].values.map { |f| f["branches_covered_percent"] }
      formatted = pcts.map { |p| format("%.2f%%", (p * 100).floor / 100.0) }.sort_by(&:to_f)

      expect(formatted).to eq %w[
        25.00% 25.00% 45.83% 50.00% 50.00% 50.00% 50.00%
        60.00% 75.00% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes source code arrays for every file" do
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("source")
        expect(file_data["source"]).to be_a(Array)
        expect(file_data["source"]).not_to be_empty
      end
    end

    it "includes covered_lines / missed_lines counts for every file" do
      coverage_data["coverage"].each_value do |file_data|
        expect(file_data).to include("covered_lines", "missed_lines")
      end
    end
  end

  describe "method coverage" do
    before do
      skip "Method coverage not supported on this Ruby" unless SimpleCov.method_coverage_supported?

      SimpleCov.enable_coverage(:method)
      formatter.format(make_result)
    end

    after { SimpleCov.clear_coverage_criteria }

    it "reports a methods totals section" do
      expect(coverage_data["total"]).to have_key("methods")
    end

    it "sets the method_coverage meta flag" do
      expect(coverage_data["meta"]["method_coverage"]).to be true
    end
  end

  describe "with branch coverage explicitly disabled" do
    before do
      SimpleCov.clear_coverage_criteria
      formatter.format(make_result)
    end

    it "omits the branches section from totals" do
      expect(coverage_data["total"]).not_to have_key("branches")
    end

    it "sets the branch_coverage meta flag to false" do
      expect(coverage_data["meta"]["branch_coverage"]).to be_falsey
    end
  end
end
