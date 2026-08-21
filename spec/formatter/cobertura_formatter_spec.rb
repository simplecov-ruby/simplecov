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
  let(:formatter_class) { SimpleCov::Formatter::CoberturaFormatter }
  let(:tmp) { Dir.mktmpdir("simplecov-cobertura-formatter-spec-") }
  let(:no_filter) { SimpleCov::Result::FilterConfig.new(filters: [], cover_filters: [], groups: {}) }
  let(:sample) { source_fixture("sample.rb") }

  # 8 relevant lines, 6 covered (0.7500). Three two-way conditions: one
  # half-taken on line 5, one untouched on line 8, and one fully taken
  # that starts on never-relevant (blank) line 10 — 6 branches, 3
  # covered (0.5000). Line 10 is blank rather than inside sample.rb's
  # :nocov: region, so it stays a never-relevant line and not a skipped
  # one.
  let(:original_result) do
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

  it "returns the XML it writes to coverage.xml in the coverage path" do
    xml = format
    expect(xml).to start_with("<?xml")
    expect(File.read(File.join(tmp, "coverage.xml"))).to eq(xml)
  end

  it "honors a custom result file name" do
    format(formatter: formatter_class.new(result_file_name: "cobertura.xml"))
    expect(File).to exist(File.join(tmp, "cobertura.xml"))
  end

  it "announces the report with its path and both coverage figures" do
    output = capture_stdout { formatter_class.new.format(result) }
    expect(output).to include("RSpec").and include(File.join(tmp, "coverage.xml"))
    expect(output).to match(/Line Coverage: .*75\.0/i)
    expect(output).to match(/Branch Coverage: .*50\.0/i)
  end

  it "totals the project on the coverage root element" do
    root = attributes(document.root)
    expect(root).to include(
      "line-rate" => "0.7500", "branch-rate" => "0.5000",
      "lines-covered" => "6", "lines-valid" => "8",
      "branches-covered" => "3", "branches-valid" => "6",
      "complexity" => "0", "version" => "0"
    )
    expect(root.fetch("timestamp")).to match(/\A\d+\z/)
  end

  it "lists SimpleCov.root as the single source" do
    sources = document.get_elements("/coverage/sources/source")
    expect(sources.map(&:text)).to eq([SimpleCov.root])
  end

  it "puts everything in one package named after the project directory when no groups are configured" do
    packages = document.get_elements("/coverage/packages/package")
    expect(packages.size).to eq(1)
    expect(attributes(packages.first)).to include(
      "name" => File.basename(SimpleCov.root),
      "line-rate" => "0.7500", "branch-rate" => "0.5000", "complexity" => "0"
    )
  end

  it "names one package per configured group" do
    groups = {"Fixtures" => SimpleCov::StringFilter.new("spec/fixtures")}
    grouped = SimpleCov::Result.new(original_result, command_name: "RSpec",
                                                     filter_config: SimpleCov::Result::FilterConfig.new(
                                                       filters: [], cover_filters: [], groups: groups
                                                     ))

    packages = document(grouped).get_elements("/coverage/packages/package")
    expect(packages.size).to eq(1)
    expect(attributes(packages.first)).to include(
      "name" => "Fixtures", "line-rate" => "0.7500", "branch-rate" => "0.5000"
    )
  end

  it "identifies each class by its project-relative path, with its own rates" do
    classes = document.get_elements("//class")
    expect(classes.size).to eq(1)
    expect(attributes(classes.first)).to include(
      "name" => "spec/fixtures/sample.rb", "filename" => "spec/fixtures/sample.rb",
      "line-rate" => "0.7500", "branch-rate" => "0.5000", "complexity" => "0"
    )
  end

  it "emits a line element per relevant line and none for never-relevant ones" do
    lines = document.get_elements("//line")
    expect(lines.map { |line| line.attributes["number"] })
      .to eq(%w[2 3 4 5 7 8 9 11])
    expect(attributes(lines.first)).to include("number" => "2", "hits" => "1", "branch" => "false")
    expect(attributes(lines.last)).to include("number" => "11", "hits" => "1", "branch" => "false")
  end

  it "tallies condition-coverage on the lines conditions start on" do
    lines = document.get_elements('//line[@branch="true"]')
    tallies = lines.to_h { |line| [line.attributes["number"], line.attributes["condition-coverage"]] }
    expect(tallies).to eq("5" => "50% (1/2)", "8" => "0% (0/2)")
  end

  it "counts a condition starting on a never-relevant line in the totals without a line element" do
    doc = document
    expect(doc.get_elements('//line[@number="10"]')).to be_empty
    expect(doc.root.attributes["branches-valid"]).to eq("6")
    expect(doc.root.attributes["branches-covered"]).to eq("3")
  end

  # A merged resultset serializes branch condition keys to strings;
  # formatting a result restored from one must tally identically.
  it "formats a result restored from a serialized resultset identically" do
    restored = SimpleCov::Result.from_hash(JSON.parse(JSON.dump(result.to_hash))).first
    allow(restored).to receive(:command_name).and_return("RSpec")

    tallies = document(restored).get_elements('//line[@branch="true"]')
                                .to_h { |line| [line.attributes["number"], line.attributes["condition-coverage"]] }
    expect(tallies).to eq("5" => "50% (1/2)", "8" => "0% (0/2)")
  end

  it "declares the Cobertura DTD" do
    expect(format).to include("<!DOCTYPE coverage SYSTEM").and include("coverage-04.dtd")
  end

  it "keeps quiet with silent: true" do
    output = capture_stdout { formatter_class.new(silent: true).format(result) }
    expect(output).to be_empty
  end

  it "escapes markup in group names" do
    groups = {"Fixtures & <Friends>" => SimpleCov::StringFilter.new("spec/fixtures")}
    grouped = SimpleCov::Result.new(original_result, command_name: "RSpec",
                                                     filter_config: SimpleCov::Result::FilterConfig.new(
                                                       filters: [], cover_filters: [], groups: groups
                                                     ))

    xml = format(grouped)
    expect(xml).to include("&amp;").and include("&lt;")
    package = REXML::Document.new(xml).get_elements("/coverage/packages/package").first
    expect(package.attributes["name"]).to eq("Fixtures & <Friends>")
  end

  it "reports a file with no relevant lines as fully covered without moving the totals" do
    with_empty = original_result.merge(source_fixture("resultset1.rb") => {"lines" => [nil, nil, nil, nil]})
    doc = document(SimpleCov::Result.new(with_empty, command_name: "RSpec", filter_config: no_filter))

    empty_class = doc.get_elements("//class").find { |klass| klass.attributes["filename"].include?("resultset1") }
    expect(attributes(empty_class)).to include("line-rate" => "1.0000")
    expect(attributes(doc.root)).to include("lines-covered" => "6", "lines-valid" => "8")
  end

  context "with a line-only report" do
    let(:original_result) do
      {sample => {"lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, nil]}}
    end

    before { allow(SimpleCov).to receive(:branch_coverage?).and_return(false) }

    # The DTD requires the branch attributes, and most projects measure
    # lines alone, so the common case must not read as an error.
    it "reports zeroed branch figures and no condition tallies" do
      doc = document
      expect(attributes(doc.root)).to include(
        "line-rate" => "0.7500", "branch-rate" => "0.0000",
        "branches-covered" => "0", "branches-valid" => "0"
      )
      expect(doc.get_elements('//line[@branch="true"]')).to be_empty
      expect(doc.get_elements("//line").filter_map { |line| line.attributes["condition-coverage"] }).to be_empty
    end
  end

  context "with hits recorded inside sample.rb's :nocov: region" do
    let(:original_result) do
      {sample => {"lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, nil, 1, 1, 1, nil, nil]}}
    end

    it "leaves skipped lines out of the rates and the line elements" do
      doc = document
      expect(attributes(doc.root)).to include("lines-covered" => "5", "lines-valid" => "7")
      expect(doc.get_elements("//line").map { |line| line.attributes["number"] }).to eq(%w[2 3 4 5 7 8 9])
    end
  end

  # Cobertura's DTD carries real method elements, which Ruby tooling
  # has historically left empty — simplecov measures method coverage,
  # so a bundled formatter can populate them.
  context "with method coverage measured" do
    let(:original_result) do
      {
        sample => {
          "lines" => [nil, 1, 1, 0, 1, nil, 1, 1, 0, nil, 1, nil, nil, nil, nil, nil],
          "methods" => {["Foo", :initialize, 3, 2, 5, 5] => 0, ["Foo", :bar, 7, 2, 9, 5] => 3}
        }
      }
    end

    before { allow(SimpleCov).to receive(:method_coverage?).and_return(true) }

    it "emits a method element per measured method under its class" do
      methods = document.get_elements("//class/methods/method")
      rates = methods.to_h { |method| [method.attributes["name"], method.attributes["line-rate"]] }
      expect(rates).to eq("Foo#initialize" => "0.0000", "Foo#bar" => "1.0000")
      expect(methods.map { |method| method.attributes["signature"] }.uniq).to eq([""])

      bar = methods.find { |method| method.attributes["name"] == "Foo#bar" }
      expect(attributes(bar.get_elements("lines/line").first)).to include("number" => "7", "hits" => "3")
    end
  end

  it "emits an empty methods element when method coverage was not measured" do
    doc = document
    expect(doc.get_elements("//class/methods").size).to eq(1)
    expect(doc.get_elements("//class/methods/method")).to be_empty
  end

  it "relativizes filenames against a root above the project" do
    old_root = SimpleCov.root
    Dir.mktmpdir("simplecov-cobertura-alt-root-") do |alt_root|
      SimpleCov.root(alt_root)
      prefix = Pathname.new(old_root).relative_path_from(Pathname.new(alt_root)).to_s

      klass = document(SimpleCov::Result.new(original_result, command_name: "RSpec",
                                                              filter_config: no_filter)).get_elements("//class").first
      expect(klass.attributes["filename"]).to eq("#{prefix}/spec/fixtures/sample.rb")
    ensure
      SimpleCov.root(old_root)
    end
  end
end
