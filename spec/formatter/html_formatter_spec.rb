# frozen_string_literal: true

require "helper"
require "fileutils"
require "json"
require "support/coverage_fixtures"

RSpec.describe SimpleCov::Formatter::HTMLFormatter do
  subject(:formatter) { described_class.new(silent: true) }

  let(:loud_formatter) { described_class.new(silent: false) }
  let(:fixtures_path)  { File.join(source_fixture_base_directory, "fixtures") }

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

  def embedded_json(dir = coverage_dir)
    html = File.read(File.join(dir, "index.html"))
    html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]
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
      .to eq("#{File.expand_path('../../lib/simplecov/formatter/html_formatter/public', __dir__)}/")
  end

  describe "#format when an existing coverage.json was written after this process started" do
    before { SimpleCov.process_start_time = Time.now }

    after { SimpleCov.process_start_time = nil }

    it "warns that a concurrent process may have written it" do
      future_timestamp = (Time.now + 3600).iso8601
      File.write(File.join(coverage_dir, "coverage.json"),
                 JSON.generate(meta: {timestamp: future_timestamp, command_name: "Other Suite"}))

      stderr = capture_stderr { formatter.format(make_result) }

      expect(stderr).to include("concurrent test run")
      expect(stderr).to include(future_timestamp)
    end

    it "does not warn when the file carries this run's command_name" do
      result = make_result
      File.write(File.join(coverage_dir, "coverage.json"),
                 JSON.generate(meta: {timestamp: (Time.now + 3600).iso8601, command_name: result.command_name}))

      expect { formatter.format(result) }.not_to output.to_stderr
    end
  end

  describe "#format under a non-UTF-8 default external encoding" do
    it "still renders the report" do
      with_default_external(Encoding::US_ASCII) do
        formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))
      end

      expect(embedded_json).to include("135°C")
    end

    it "still renders from a coverage.json carrying non-ASCII source" do
      formatter.format(make_result({"utf-8.rb" => {"lines" => [1]}}))

      Dir.mktmpdir do |dir|
        with_default_external(Encoding::US_ASCII) do
          formatter.format_from_json(File.join(coverage_dir, "coverage.json"), dir)
        end

        expect(embedded_json(dir)).to include("135°C")
      end
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

    it "overwrites read-only assets from prior runs without raising EACCES" do
      formatter.format(make_result)
      assets = Dir[File.join(coverage_dir, "*")].select { |path| File.file?(path) }
      modes = assets.to_h { |path| [path, File.stat(path).mode & 0o777] }
      assets.each { |path| File.chmod(0o444, path) }

      expect { formatter.format(make_result) }.not_to raise_error
    ensure
      modes&.each { |path, mode| File.chmod(mode, path) if File.exist?(path) }
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
    it "keeps embedded </script>, <!-- and backslash sequences intact" do
      hostile = {"source" => ["</script><script>alert(1)</script>", "<!-- <script> -->", "a\\1b\\\\c"]}
      html = formatter.send(:render_report, JSON.generate(hostile))
      captured = html[%r{window\.SIMPLECOV_DATA = (.*?);</script>}m, 1]

      expect(captured).not_to include("<")
      expect(JSON.parse(captured)).to eq hostile
    end

    it "embeds a non-ASCII payload under a non-UTF-8 default external encoding" do
      html = with_default_external(Encoding::US_ASCII) do
        formatter.send(:render_report, JSON.generate({"source" => ["135°C"]}))
      end

      expect(html).to include(%(window.SIMPLECOV_DATA = {"source":["135°C"]};))
    end

    it "substitutes the payload into the template, leaving the rest of the page" do
      template = File.read(File.join(formatter.send(:public_dir), "index.html"), encoding: Encoding::UTF_8)

      html = formatter.send(:render_report, "{}")

      expect(html).to eq(template.sub(described_class::DATA_MARKER,
                                      %(<script>window.SIMPLECOV_DATA = {};</script>)))
      expect(html).not_to include(described_class::DATA_MARKER)
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

    before { formatter.format(make_result) }

    it "writes a single index.html into the target dir" do
      described_class.new.format_from_json(json_path, standalone_dir)

      expect(Dir.children(standalone_dir)).to eq %w[index.html]
    end

    it "writes the standalone report as bytes, not text" do
      allow(SimpleCov::AtomicFile).to receive(:write).and_call_original

      described_class.new.format_from_json(json_path, standalone_dir)

      expect(SimpleCov::AtomicFile).to have_received(:write)
        .with(File.join(standalone_dir, "index.html"), anything, binary: true)
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
        .to raise_error(SimpleCov::CoverageJSON::Error, /array of source strings.*source_in_json true/)
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

    it "rejects metadata that would crash the viewer before creating the target dir" do
      data = JSON.parse(File.read(json_path))
      data.fetch("meta").delete("timestamp")
      File.write(json_path, JSON.dump(data))

      expect { described_class.new.format_from_json(json_path, standalone_dir) }
        .to raise_error(SimpleCov::CoverageJSON::Error, /meta\.timestamp must be a string/)
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
