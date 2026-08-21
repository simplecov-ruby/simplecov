# frozen_string_literal: true

require "helper"
require "fileutils"
require "json"
require "rexml/document"
require "tmpdir"

# The behavioral bar for the Cobertura formatter #1266 proposes to
# bundle: the behavior the format's consumers (Jenkins, GitLab, and
# Azure Pipelines among them) expect of it. Written ahead of the
# implementation on purpose: every example fails until
# SimpleCov::Formatter::CoberturaFormatter exists.
RSpec.describe "SimpleCov::Formatter::CoberturaFormatter" do
  let(:tmp) { Dir.mktmpdir("simplecov-cobertura-formatter-spec-") }
  let(:result) { SimpleCov::Result.new(original_result, command_name: "RSpec", filter_config: no_filter) }

  around do |example|
    previous = SimpleCov.coverage_dir
    SimpleCov.coverage_dir(tmp)
    example.run
  ensure
    SimpleCov.coverage_dir(previous)
    FileUtils.rm_rf(tmp)
  end

  before { allow(SimpleCov).to receive(:branch_coverage?).and_return(true) }

  def formatter_class = SimpleCov::Formatter::CoberturaFormatter

  def sample = source_fixture("sample.rb")

  def no_filter = SimpleCov::Result::FilterConfig.new(filters: [], cover_filters: [], groups: {})

  # 8 relevant lines, 6 covered (0.7500). Three two-way conditions: one
  # half-taken on line 5, one untouched on line 8, and one fully taken
  # that starts on never-relevant (blank) line 10 — 6 branches, 3
  # covered (0.5000). Line 10 is blank rather than inside sample.rb's
  # :nocov: region, so it stays a never-relevant line and not a skipped
  # one.
  def original_result
    {
      sample => {
        "lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, nil],
        "branches" => {
          [:if, 0, 5, 4, 5, 20] => {[:then, 1, 5, 6, 5, 10] => 1, [:else, 2, 5, 15, 5, 20] => 0},
          [:if, 3, 8, 4, 8, 20] => {[:then, 4, 8, 6, 8, 10] => 0, [:else, 5, 8, 15, 8, 20] => 0},
          [:if, 6, 10, 4, 10, 20] => {[:then, 7, 10, 6, 10, 10] => 1, [:else, 8, 10, 15, 10, 20] => 2}
        }
      }
    }
  end

  def grouped_result(groups)
    filter_config = SimpleCov::Result::FilterConfig.new(filters: [], cover_filters: [], groups: groups)
    SimpleCov::Result.new(original_result, command_name: "RSpec", filter_config: filter_config)
  end

  def format(target = result, formatter: formatter_class.new)
    xml = nil
    capture_stdout { xml = formatter.format(target) }
    xml
  end

  def capture_stdout
    previous = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous
  end

  def document(target = result, **options)
    REXML::Document.new(format(target, **options))
  end

  def attributes(element)
    element.attributes.each_attribute.to_h { |attribute| [attribute.name, attribute.value] }
  end

  def condition_tallies(doc)
    doc.get_elements('//line[@branch="true"]')
      .to_h { |line| [line.attributes["number"], line.attributes["condition-coverage"]] }
  end

  describe "the report it writes" do
    let(:xml) { format }

    it "returns an XML document" do
      expect(xml).to start_with("<?xml")
    end

    it "writes that same document to coverage.xml in the coverage path" do
      expect(File.read(File.join(tmp, "coverage.xml"))).to eq(xml)
    end

    it "declares the Cobertura DTD" do
      expect(xml).to include("<!DOCTYPE coverage SYSTEM").and include("coverage-04.dtd")
    end
  end

  it "honors a custom result file name" do
    format(formatter: formatter_class.new(result_file_name: "cobertura.xml"))

    expect(File).to exist(File.join(tmp, "cobertura.xml"))
  end

  describe "the announcement it prints" do
    let(:output) { capture_stdout { formatter_class.new.format(result) } }

    it "names the command" do
      expect(output).to include("RSpec")
    end

    it "names the file it wrote" do
      expect(output).to include(File.join(tmp, "coverage.xml"))
    end

    it "reports line coverage" do
      expect(output).to match(/Line Coverage: .*75\.0/i)
    end

    it "reports branch coverage" do
      expect(output).to match(/Branch Coverage: .*50\.0/i)
    end

    it "keeps quiet with silent: true" do
      expect(capture_stdout { formatter_class.new(silent: true).format(result) }).to be_empty
    end
  end

  describe "the coverage root element" do
    let(:root) { attributes(document.root) }

    it "totals the project's rates" do
      expect(root).to include("line-rate" => "0.7500", "branch-rate" => "0.5000")
    end

    it "totals the project's line and branch tallies" do
      expect(root).to include(
        "lines-covered" => "6", "lines-valid" => "8",
        "branches-covered" => "3", "branches-valid" => "6"
      )
    end

    it "carries the attributes the DTD requires but SimpleCov does not measure" do
      expect(root).to include("complexity" => "0", "version" => "0")
    end

    it "stamps an integer timestamp" do
      expect(root.fetch("timestamp")).to match(/\A\d+\z/)
    end
  end

  it "lists SimpleCov.root as the single source" do
    sources = document.get_elements("/coverage/sources/source")

    expect(sources.map(&:text)).to eq([SimpleCov.root])
  end

  describe "packages when no groups are configured" do
    let(:packages) { document.get_elements("/coverage/packages/package") }

    it "puts everything in one package" do
      expect(packages.size).to eq(1)
    end

    it "names it after the project directory" do
      expect(attributes(packages.first)).to include("name" => File.basename(SimpleCov.root))
    end

    it "carries the project's rates on it" do
      expect(attributes(packages.first)).to include(
        "line-rate" => "0.7500", "branch-rate" => "0.5000", "complexity" => "0"
      )
    end
  end

  describe "packages when groups are configured" do
    let(:packages) do
      groups = {"Fixtures" => SimpleCov::StringFilter.new("spec/fixtures")}
      document(grouped_result(groups)).get_elements("/coverage/packages/package")
    end

    it "names one package per group" do
      expect(packages.size).to eq(1)
    end

    it "names it after the group" do
      expect(attributes(packages.first)).to include("name" => "Fixtures")
    end

    it "carries the group's rates on it" do
      expect(attributes(packages.first)).to include("line-rate" => "0.7500", "branch-rate" => "0.5000")
    end
  end

  describe "the class element for a covered file" do
    let(:classes) { document.get_elements("//class") }

    it "emits one per file" do
      expect(classes.size).to eq(1)
    end

    it "identifies it by its project-relative path" do
      expect(attributes(classes.first)).to include(
        "name" => "spec/fixtures/sample.rb", "filename" => "spec/fixtures/sample.rb"
      )
    end

    it "carries the file's own rates" do
      expect(attributes(classes.first)).to include(
        "line-rate" => "0.7500", "branch-rate" => "0.5000", "complexity" => "0"
      )
    end
  end

  describe "the line elements" do
    let(:lines) { document.get_elements("//line") }

    it "emits one per relevant line and none for never-relevant ones" do
      expect(lines.map { |line| line.attributes["number"] }).to eq(%w[2 3 4 5 7 8 9 11])
    end

    it "records the hits on the first" do
      expect(attributes(lines.first)).to include("number" => "2", "hits" => "1", "branch" => "false")
    end

    it "records the hits on the last" do
      expect(attributes(lines.last)).to include("number" => "11", "hits" => "1", "branch" => "false")
    end
  end

  it "tallies condition-coverage on the lines conditions start on" do
    expect(condition_tallies(document)).to eq("5" => "50% (1/2)", "8" => "0% (0/2)")
  end

  describe "a condition starting on a never-relevant line" do
    let(:doc) { document }

    it "emits no line element for it" do
      expect(doc.get_elements('//line[@number="10"]')).to be_empty
    end

    it "still counts its branches among the valid ones" do
      expect(doc.root.attributes["branches-valid"]).to eq("6")
    end

    it "still counts the branches it took among the covered ones" do
      expect(doc.root.attributes["branches-covered"]).to eq("3")
    end
  end

  # A merged resultset serializes branch condition keys to strings;
  # formatting a result restored from one must tally identically.
  it "formats a result restored from a serialized resultset identically" do
    restored = SimpleCov::Result.from_hash(JSON.parse(JSON.dump(result.to_hash))).first
    allow(restored).to receive(:command_name).and_return("RSpec")

    expect(condition_tallies(document(restored))).to eq("5" => "50% (1/2)", "8" => "0% (0/2)")
  end

  describe "a group name containing markup" do
    let(:xml) do
      groups = {"Fixtures & <Friends>" => SimpleCov::StringFilter.new("spec/fixtures")}
      format(grouped_result(groups))
    end

    it "escapes the ampersand" do
      expect(xml).to include("&amp;")
    end

    it "escapes the angle bracket" do
      expect(xml).to include("&lt;")
    end

    it "round-trips the name through a parser" do
      package = REXML::Document.new(xml).get_elements("/coverage/packages/package").first

      expect(package.attributes["name"]).to eq("Fixtures & <Friends>")
    end
  end

  describe "a file with no relevant lines" do
    let(:doc) do
      with_empty = original_result.merge(source_fixture("resultset1.rb") => {"lines" => [nil, nil, nil, nil]})
      document(SimpleCov::Result.new(with_empty, command_name: "RSpec", filter_config: no_filter))
    end

    it "reports it as fully covered" do
      empty_class = doc.get_elements("//class").find { |klass| klass.attributes["filename"].include?("resultset1") }

      expect(attributes(empty_class)).to include("line-rate" => "1.0000")
    end

    it "leaves the project totals where they were" do
      expect(attributes(doc.root)).to include("lines-covered" => "6", "lines-valid" => "8")
    end
  end

  context "with a line-only report" do
    let(:doc) { document }

    before { allow(SimpleCov).to receive(:branch_coverage?).and_return(false) }

    def original_result
      {sample => {"lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, nil]}}
    end

    # The DTD requires the branch attributes, and most projects measure
    # lines alone, so the common case must not read as an error.
    it "still reports the line rate" do
      expect(attributes(doc.root)).to include("line-rate" => "0.7500")
    end

    it "reports zeroed branch figures rather than omitting them" do
      expect(attributes(doc.root)).to include(
        "branch-rate" => "0.0000", "branches-covered" => "0", "branches-valid" => "0"
      )
    end

    it "marks no line as a branch" do
      expect(doc.get_elements('//line[@branch="true"]')).to be_empty
    end

    it "tallies no condition coverage" do
      tallies = doc.get_elements("//line").filter_map { |line| line.attributes["condition-coverage"] }

      expect(tallies).to be_empty
    end
  end

  context "with hits recorded inside sample.rb's :nocov: region" do
    let(:doc) { document }

    def original_result
      {sample => {"lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, nil, 1, 1, 1, nil, nil]}}
    end

    it "leaves the skipped lines out of the rates" do
      expect(attributes(doc.root)).to include("lines-covered" => "5", "lines-valid" => "7")
    end

    it "leaves the skipped lines out of the line elements" do
      expect(doc.get_elements("//line").map { |line| line.attributes["number"] }).to eq(%w[2 3 4 5 7 8 9])
    end
  end

  # Cobertura's DTD carries real method elements, which Ruby tooling
  # has historically left empty — simplecov measures method coverage,
  # so a bundled formatter can populate them.
  context "with method coverage measured" do
    let(:methods) { document.get_elements("//class/methods/method") }

    before { allow(SimpleCov).to receive(:method_coverage?).and_return(true) }

    def original_result
      {
        sample => {
          "lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, nil],
          "methods" => {["Foo", :initialize, 3, 2, 5, 5] => 0, ["Foo", :bar, 7, 2, 9, 5] => 3}
        }
      }
    end

    it "emits one method element per measured method, rated by its own hits" do
      rates = methods.to_h { |method| [method.attributes["name"], method.attributes["line-rate"]] }

      expect(rates).to eq("Foo#initialize" => "0.0000", "Foo#bar" => "1.0000")
    end

    it "leaves the signature empty" do
      expect(methods.map { |method| method.attributes["signature"] }.uniq).to eq([""])
    end

    it "emits a line element at each method's start line" do
      bar = methods.find { |method| method.attributes["name"] == "Foo#bar" }

      expect(attributes(bar.get_elements("lines/line").first)).to include("number" => "7", "hits" => "3")
    end
  end

  describe "the methods element when method coverage was not measured" do
    let(:doc) { document }

    it "emits one per class" do
      expect(doc.get_elements("//class/methods").size).to eq(1)
    end

    it "leaves it empty" do
      expect(doc.get_elements("//class/methods/method")).to be_empty
    end
  end

  describe "a SimpleCov.root above the project" do
    let(:alt_root) { Dir.mktmpdir("simplecov-cobertura-alt-root-") }
    let(:project_root) { SimpleCov.root }
    let(:prefix) { Pathname.new(project_root).relative_path_from(Pathname.new(alt_root)).to_s }

    around do |example|
      project_root # memoize the real root before moving it
      SimpleCov.root(alt_root)
      example.run
    ensure
      SimpleCov.root(project_root)
      FileUtils.rm_rf(alt_root)
    end

    it "relativizes filenames against it" do
      klass = document.get_elements("//class").first

      expect(klass.attributes["filename"]).to eq("#{prefix}/spec/fixtures/sample.rb")
    end
  end
end
