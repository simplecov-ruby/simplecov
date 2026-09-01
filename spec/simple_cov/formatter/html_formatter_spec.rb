# frozen_string_literal: true

require "helper"
require "fileutils"
require "json"
require "support/coverage_fixtures"

RSpec.describe SimpleCov::Formatter::HTMLFormatter do
  subject(:formatter) { described_class.new(silent: true) }

  let(:loud_formatter) { described_class.new(silent: false) }
  let(:fixtures_path) { File.join(source_fixture_base_directory, "fixtures") }

  let(:tmp_root) { Dir.mktmpdir("simplecov-html-formatter-") }
  let(:coverage_dir) { File.join(tmp_root, "coverage") }

  before do
    FileUtils.mkdir_p(coverage_dir)
    allow(SimpleCov).to receive_messages(coverage_dir: coverage_dir, coverage_path: coverage_dir)
    SimpleCov::SourceFile::SkipChunks.nocov_warned.clear
  end

  after { FileUtils.rm_rf(tmp_root) }

  def fixture_path(name)
    File.join(fixtures_path, name)
  end

  def make_result(coverage = {"sample.rb" => CoverageFixtures::SAMPLE_RB})
    SimpleCov::Result.new(coverage.transform_keys { |name| fixture_path(name) })
  end

  def report_html(dir = coverage_dir)
    File.read(File.join(dir, "index.html"))
  end

  def embedded_json(dir = coverage_dir)
    report_html(dir)[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
  end

  def coverage_data(dir = coverage_dir)
    JSON.parse(embedded_json(dir))
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
    $VERBOSE = nil
    Encoding.default_external = encoding
  ensure
    $VERBOSE = verbose
  end

  describe "DATA_MARKER" do
    it "is present exactly once in the compiled template" do
      template = File.read(File.join(formatter.send(:public_dir), "index.html"))
      expect(template.scan(described_class::DATA_MARKER).count).to eq 1
    end
  end

  it "reads its template from the assets directory beside the formatter" do
    expect(formatter.send(:public_dir))
      .to eq("#{File.expand_path("../../../lib/simplecov/formatter/html_formatter/public", __dir__)}/")
  end

  describe "#format when an existing coverage.json was written after this process started" do
    before { SimpleCov.process_start_time = Time.now }

    after { SimpleCov.process_start_time = nil }

    it "warns that a concurrent process may have written it" do
      future_timestamp = (Time.now + 3600).iso8601
      File.write(File.join(coverage_dir, "coverage.json"),
        JSON.generate(meta: {timestamp: future_timestamp, command_name: "Other Suite"}))

      stderr = capture_stderr { formatter.format(make_result) }

      expect(stderr).to include("concurrent test run").and include(future_timestamp)
    end

    it "does not warn when the file carries this run's command_name" do
      result = make_result
      File.write(File.join(coverage_dir, "coverage.json"),
        JSON.generate(meta: {timestamp: (Time.now + 3600).iso8601, command_name: result.command_name}))

      expect { formatter.format(result) }.not_to output.to_stderr
    end
  end

  describe "#format under a non-UTF-8 default external encoding" do
    def render_standalone_as_ascii(dir)
      with_default_external(Encoding::US_ASCII) do
        formatter.format_from_json(File.join(coverage_dir, "coverage.json"), dir)
      end
    end

    it "still renders the report" do
      with_default_external(Encoding::US_ASCII) do
        formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))
      end

      expect(embedded_json).to include("135°C")
    end

    it "still renders from a coverage.json carrying non-ASCII source" do
      formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))

      Dir.mktmpdir do |dir|
        render_standalone_as_ascii(dir)

        expect(embedded_json(dir)).to include("135°C")
      end
    end
  end

  describe "#format with output_dir" do
    let(:output_dir) { Dir.mktmpdir("simplecov-html-formatter-output-") }

    before { described_class.new(silent: true, output_dir: output_dir).format(make_result) }

    after { FileUtils.rm_rf(output_dir) }

    it "writes index.html into the explicit directory" do
      expect(File.exist?(File.join(output_dir, "index.html"))).to be true
    end

    it "writes nothing into SimpleCov.coverage_path" do
      expect(File.exist?(File.join(coverage_dir, "index.html"))).to be false
    end
  end

  describe "#format" do
    before { formatter.format(make_result) }

    def with_read_only_assets
      assets = Dir[File.join(coverage_dir, "*")].select { |path| File.file?(path) }
      modes = assets.to_h { |path| [path, File.stat(path).mode & 0o777] }
      assets.each { |path| File.chmod(0o444, path) }
      yield
    ensure
      modes&.each { |path, mode| File.chmod(mode, path) if File.exist?(path) }
    end

    it "writes no files besides index.html and coverage.json" do
      expect(Dir.children(coverage_dir).sort).to eq %w[coverage.json index.html]
    end

    it "writes the report as bytes, not text" do
      allow(SimpleCov::AtomicFile).to receive(:write).and_call_original

      formatter.format(make_result)

      expect(SimpleCov::AtomicFile).to have_received(:write)
        .with(File.join(coverage_dir, "index.html"), anything, binary: true)
    end

    it "removes the sibling files a pre-1.0.4 report left behind" do
      described_class::LEGACY_REPORT_FILES.each { |name| FileUtils.touch(File.join(coverage_dir, name)) }
      FileUtils.touch(File.join(coverage_dir, "unrelated.txt"))

      formatter.format(make_result)

      expect(Dir.children(coverage_dir).sort).to eq %w[coverage.json index.html unrelated.txt]
    end

    it "embeds parseable JSON in the report" do
      data = coverage_data

      expect(data).to be_a(Hash).and include("meta", "coverage", "total")
    end

    it "is a self-contained page with the viewer's JS and CSS inlined" do
      expect(report_html).to include("<!DOCTYPE html>", "<style>", "<script>")
    end

    it "references no external asset files" do
      expect(report_html).not_to include("src=\"application.js\"", "href=\"application.css\"", "coverage_data.js")
    end

    it "ships no favicon images (the viewer draws one from the live palette)" do
      expect(report_html).not_to include("data:image/png", "favicon")
    end

    it "embeds the source code of each file in the coverage payload" do
      expect(coverage_data["coverage"].values.first).to include("source" => a_kind_of(Array))
    end

    it "embeds a source array that is not empty" do
      expect(coverage_data["coverage"].values.first["source"]).not_to be_empty
    end

    it "embeds the metadata section in the coverage payload" do
      expect(coverage_data["meta"]).to include(
        "simplecov_version", "command_name", "project_name", "timestamp", "root",
        "branch_coverage" => be(true).or(be(false)),
        "method_coverage" => be(true).or(be(false))
      )
    end

    it "overwrites read-only assets from prior runs without raising EACCES" do
      formatter.format(make_result)

      with_read_only_assets do
        expect { formatter.format(make_result) }.not_to raise_error
      end
    end
  end

  describe "#format when source_in_json is false" do
    let(:result) { make_result }
    let(:embedded) { coverage_data }
    let(:external) { JSON.parse(File.read(File.join(coverage_dir, "coverage.json"))) }

    before do
      allow(SimpleCov).to receive(:source_in_json).and_return(false)
      allow(SimpleCov::Formatter::JSONFormatter).to receive(:build_hash).and_call_original
      formatter.format(result)
    end

    it "builds one source-bearing payload" do
      expect(SimpleCov::Formatter::JSONFormatter).to have_received(:build_hash)
        .once.with(result, include_source: true)
    end

    it "keeps the source in the embedded payload" do
      expect(embedded.fetch("coverage").values.first.fetch("source")).not_to be_empty
    end

    it "derives coverage.json from that payload without mutating it" do
      coverage = embedded.fetch("coverage").transform_values { |file| file.except("source") }

      expect(external).to eq(embedded.merge("coverage" => coverage))
    end
  end

  describe "#render_report escaping" do
    context "with embedded </script>, <!-- and backslash sequences" do
      let(:hostile) { {"source" => ["</script><script>alert(1)</script>", "<!-- <script> -->", "a\\1b\\\\c"]} }
      let(:captured) do
        html = formatter.send(:render_report, JSON.generate(hostile))
        html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
      end

      it "escapes every angle bracket out of the payload" do
        expect(captured).not_to include("<")
      end

      it "keeps the payload intact" do
        expect(JSON.parse(captured)).to eq hostile
      end
    end

    it "embeds a non-ASCII payload under a non-UTF-8 default external encoding" do
      html = with_default_external(Encoding::US_ASCII) do
        formatter.send(:render_report, JSON.generate({"source" => ["135°C"]}))
      end

      expect(html).to include(%(window.SIMPLECOV_DATA = {"source":["135°C"]};))
    end

    context "when substituting the payload into the template" do
      let(:template) { File.read(File.join(formatter.send(:public_dir), "index.html"), encoding: Encoding::UTF_8) }
      let(:rendered) { formatter.send(:render_report, "{}") }

      it "leaves the rest of the page" do
        expect(rendered).to eq(template.sub(described_class::DATA_MARKER,
          %(<script>window.SIMPLECOV_DATA = {};</script>)))
      end

      it "consumes the data marker" do
        expect(rendered).not_to include(described_class::DATA_MARKER)
      end
    end

    it "raises a clear error when the template is missing the data marker" do
      allow(File).to receive(:read).and_return("<html></html>")

      expect { formatter.send(:render_report, "{}") }.to raise_error(
        RuntimeError,
        %(SimpleCov's HTML template is missing its "<!-- SIMPLECOV_COVERAGE_DATA -->" marker)
      )
    end
  end

  describe "#format status" do
    it "emits the HTML report's entry point" do
      stderr = capture_stderr { loud_formatter.format(make_result) }

      expected = "Coverage report generated for RSpec to #{SimpleCov.coverage_dir}/index.html"
      expect(stderr.lines.first.chomp).to eq(expected)
    end
  end

  describe "#format_from_json" do
    let(:standalone_dir) { File.join(coverage_dir, "standalone") }
    let(:json_path) { File.join(coverage_dir, "coverage.json") }
    let(:index_path) { File.join(standalone_dir, "index.html") }

    before { formatter.format(make_result) }

    def parsed_json
      JSON.parse(File.read(json_path))
    end

    def rewrite_json(document)
      File.write(json_path, JSON.dump(document))
    end

    def write_existing_report
      FileUtils.mkdir_p(standalone_dir)
      File.write(index_path, "existing report")
    end

    def strip_source
      data = parsed_json
      data.fetch("coverage").each_value { |file| file.delete("source") }
      rewrite_json(data)
    end

    def expect_rejection(message)
      expect { described_class.new.format_from_json(json_path, standalone_dir) }
        .to raise_error(SimpleCov::CoverageJSON::Error, message)
    end

    it "writes a single index.html into the target dir" do
      described_class.new.format_from_json(json_path, standalone_dir)

      expect(Dir.children(standalone_dir)).to eq %w[index.html]
    end

    it "writes the standalone report as bytes, not text" do
      allow(SimpleCov::AtomicFile).to receive(:write).and_call_original

      described_class.new.format_from_json(json_path, standalone_dir)

      expect(SimpleCov::AtomicFile).to have_received(:write)
        .with(index_path, anything, binary: true)
    end

    it "embeds data with the same shape as the in-process format run" do
      described_class.new.format_from_json(json_path, standalone_dir)

      data = coverage_data(standalone_dir)

      expect(data).to include("meta", "coverage")
    end

    it "rejects missing viewer sections before creating the target dir" do
      rewrite_json(parsed_json.except("groups"))
      expect_rejection(/"groups" must be an object/)

      expect(Dir).not_to exist(standalone_dir)
    end

    it "rejects source-less coverage without replacing an existing report" do
      write_existing_report
      strip_source
      expect_rejection(/array of source strings.*source_in_json true/)

      expect(File.read(index_path)).to eq("existing report")
    end

    it "rejects coverage entries that are not objects" do
      data = parsed_json
      data.fetch("coverage")[data.fetch("coverage").keys.first] = []
      rewrite_json(data)
      expect_rejection(/coverage entry .* must be an object/)

      expect(Dir).not_to exist(standalone_dir)
    end

    it "rejects metadata that would crash the viewer before creating the target dir" do
      data = parsed_json
      data.fetch("meta").delete("timestamp")
      rewrite_json(data)
      expect_rejection(/meta\.timestamp must be a string/)

      expect(Dir).not_to exist(standalone_dir)
    end
  end

  describe "integration with the full ALL_FIXTURES set" do
    let!(:original_criteria) { SimpleCov.coverage_criteria.dup }
    let!(:original_filters) { SimpleCov.filters.dup }

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

    def formatted_percents(key)
      percents = coverage_data["coverage"].values.map { |file| file[key] }
      percents.map { |percent| format("%.2f%%", (percent * 100).floor / 100.0) }.sort_by(&:to_f)
    end

    it "computes the expected total line-coverage percentage" do
      expect(coverage_data["total"]["lines"]["percent"]).to be_within(0.01).of(75.28)
    end

    it "reports the expected per-file line coverages" do
      expect(formatted_percents("lines_covered_percent")).to eq %w[
        57.14% 64.28% 66.66% 66.66% 80.00% 85.71%
        85.71% 85.71% 100.00% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes branch totals when branch coverage is enabled" do
      skip "Branch coverage not supported on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect(coverage_data["total"]).to have_key("branches")
    end

    it "includes per-file branch stats when branch coverage is enabled" do
      skip "Branch coverage not supported on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect(coverage_data["coverage"].values).to all(include("branches", "branches_covered_percent"))
    end

    it "reports the expected per-file branch coverages" do
      skip "Branch coverage not supported on this Ruby" unless SimpleCov.branch_coverage_supported?

      expect(formatted_percents("branches_covered_percent")).to eq %w[
        25.00% 25.00% 45.83% 50.00% 50.00% 50.00% 50.00%
        60.00% 75.00% 100.00% 100.00% 100.00% 100.00%
      ]
    end

    it "includes a source code array for every file" do
      expect(coverage_data["coverage"].values).to all(include("source" => a_kind_of(Array)))
    end

    it "includes no empty source code array" do
      expect(coverage_data["coverage"].values.map { |file| file["source"].size }).to all(be_positive)
    end

    it "includes covered_lines / missed_lines counts for every file" do
      expect(coverage_data["coverage"].values).to all(include("covered_lines", "missed_lines"))
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
