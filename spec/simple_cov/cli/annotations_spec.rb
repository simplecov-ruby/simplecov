# frozen_string_literal: true

require "helper"
require "json"
require "simplecov/cli"

RSpec.describe SimpleCov::CLI::Annotations, mutant_expression: "SimpleCov::CLI::Annotations*" do
  let(:stdout) { StringIO.new }

  def missed_lines = described_class.diagnostics("lib/a.rb", [41, 42, 43, 47], :line)

  def missed_branch = described_class.diagnostics("lib/a.rb", [39], :branch)

  def missed_method = described_class.diagnostics("lib/b.rb", [7], :method)

  def diagnostics = missed_lines + missed_branch + missed_method

  def emit(kind, diagnostics = self.diagnostics)
    described_class.emit(stdout, kind, diagnostics)
    stdout.string
  end

  describe ".diagnostics" do
    it "collapses contiguous missed lines into one diagnostic per range" do
      expect(missed_lines).to eq([
        {path: "lib/a.rb", first: 41, last: 43, criterion: :line, message: "Not covered by tests"},
        {path: "lib/a.rb", first: 47, last: 47, criterion: :line, message: "Not covered by tests"}
      ])
    end

    it "splits at a gap of one line" do
      expect(described_class.diagnostics("x.rb", [1, 3], :line).map { |d| d.fetch(:first) }).to eq([1, 3])
    end

    it "names a missed branch" do
      expect(missed_branch.first.fetch(:message)).to eq("Branch not covered by tests")
    end

    it "names a missed method" do
      expect(missed_method.first.fetch(:message)).to eq("Method not covered by tests")
    end

    it "is empty when nothing was missed" do
      expect(described_class.diagnostics("x.rb", [], :line)).to eq([])
    end
  end

  describe ".issue" do
    it "accepts every known kind" do
      described_class::KINDS.each do |kind|
        expect(described_class.issue(annotate: kind, json: false)).to be_nil
      end
    end

    it "is nil without --annotate" do
      expect(described_class.issue(annotate: nil, json: true)).to be_nil
    end

    it "names the kinds it knows for an unknown one" do
      expect(described_class.issue(annotate: "jenkins", json: false))
        .to eq('unknown --annotate "jenkins" (expected github, gitlab, rdjson, azure, teamcity, or buildkite)')
    end

    it "refuses --json" do
      expect(described_class.issue(annotate: "github", json: true)).to eq("cannot combine --annotate with --json")
    end
  end

  describe "github" do
    let(:workflow_commands) do
      <<~OUT
        ::warning file=lib/a.rb,line=41,endLine=43::Not covered by tests
        ::warning file=lib/a.rb,line=47,endLine=47::Not covered by tests
        ::warning file=lib/a.rb,line=39,endLine=39::Branch not covered by tests
        ::warning file=lib/b.rb,line=7,endLine=7::Method not covered by tests
      OUT
    end

    it "emits one ::warning workflow command per diagnostic" do
      expect(emit("github")).to eq(workflow_commands)
    end

    it "emits nothing for no diagnostics" do
      expect(emit("github", [])).to be_empty
    end
  end

  describe "gitlab" do
    let(:report) { JSON.parse(emit("gitlab")) }
    let(:finding) do
      {"description" => "Not covered by tests",
       "check_name" => "coverage",
       "fingerprint" => Digest::SHA256.hexdigest("lib/a.rb:41-43:line"),
       "severity" => "minor",
       "location" => {"path" => "lib/a.rb", "lines" => {"begin" => 41, "end" => 43}}}
    end

    it "emits a Code Quality finding per diagnostic" do
      expect(report.first).to eq(finding)
    end

    it "carries every diagnostic" do
      expect(report.map { |finding| finding.dig("location", "lines", "begin") }).to eq([41, 47, 39, 7])
    end

    it "gives each finding a distinct fingerprint" do
      expect(report.map { |finding| finding.fetch("fingerprint") }.uniq.size).to eq(4)
    end

    it "emits an empty array for no diagnostics" do
      expect(emit("gitlab", [])).to eq("[]\n")
    end

    it "pretty-prints so the artifact is readable" do
      expect(emit("gitlab")).to start_with("[\n  {\n")
    end
  end

  describe "rdjson" do
    let(:result) { JSON.parse(emit("rdjson")) }
    let(:diagnostic) do
      {"message" => "Not covered by tests",
       "location" => {"path" => "lib/a.rb", "range" => {"start" => {"line" => 41}, "end" => {"line" => 43}}},
       "severity" => "WARNING",
       "code" => {"value" => "line"}}
    end
    let(:empty_result) do
      <<~OUT
        {
          "source": {
            "name": "simplecov",
            "url": "https://github.com/simplecov-ruby/simplecov"
          },
          "severity": "WARNING",
          "diagnostics": []
        }
      OUT
    end

    it "names simplecov as the source" do
      expect(result.fetch("source")).to eq("name" => "simplecov", "url" => "https://github.com/simplecov-ruby/simplecov")
    end

    it "emits a WARNING diagnostic per range" do
      expect(result.fetch("diagnostics").first).to eq(diagnostic)
    end

    it "spells the criterion as a string" do
      expect(described_class.rdjson_diagnostic(missed_lines.first)).to eq(diagnostic)
    end

    it "carries every diagnostic" do
      expect(result.fetch("diagnostics").map { |d| d.dig("code", "value") }).to eq(%w[line line branch method])
    end

    it "sets the result severity" do
      expect(result.fetch("severity")).to eq("WARNING")
    end

    it "emits an empty result for no diagnostics" do
      expect(emit("rdjson", [])).to eq(empty_result)
    end
  end

  describe "azure" do
    let(:logging_commands) do
      <<~OUT
        ##vso[task.logissue type=warning;sourcepath=lib/a.rb;linenumber=41]Not covered by tests (lines 41-43)
        ##vso[task.logissue type=warning;sourcepath=lib/a.rb;linenumber=47]Not covered by tests
        ##vso[task.logissue type=warning;sourcepath=lib/a.rb;linenumber=39]Branch not covered by tests
        ##vso[task.logissue type=warning;sourcepath=lib/b.rb;linenumber=7]Method not covered by tests
      OUT
    end

    it "emits one logissue command per diagnostic, naming a multi-line range in the message" do
      expect(emit("azure")).to eq(logging_commands)
    end

    it "escapes the property delimiters in a path" do
      diagnostics = described_class.diagnostics("odd;name]%\r\n.rb", [1], :line)

      expect(emit("azure", diagnostics))
        .to eq("##vso[task.logissue type=warning;sourcepath=odd%3Bname%5D%AZP25%0D%0A.rb;linenumber=1]Not covered by tests\n")
    end

    it "emits nothing for no diagnostics" do
      expect(emit("azure", [])).to be_empty
    end
  end

  describe "teamcity" do
    let(:service_messages) do
      <<~OUT
        ##teamcity[inspectionType id='simplecov.line' name='Not covered by tests' description='Lines the tests never executed' category='Code coverage']
        ##teamcity[inspection typeId='simplecov.line' message='Not covered by tests (lines 41-43)' file='lib/a.rb' line='41' SEVERITY='WARNING']
        ##teamcity[inspection typeId='simplecov.line' message='Not covered by tests' file='lib/a.rb' line='47' SEVERITY='WARNING']
        ##teamcity[inspectionType id='simplecov.branch' name='Branch not covered by tests' description='Branches the tests never took' category='Code coverage']
        ##teamcity[inspection typeId='simplecov.branch' message='Branch not covered by tests' file='lib/a.rb' line='39' SEVERITY='WARNING']
        ##teamcity[inspectionType id='simplecov.method' name='Method not covered by tests' description='Methods the tests never called' category='Code coverage']
        ##teamcity[inspection typeId='simplecov.method' message='Method not covered by tests' file='lib/b.rb' line='7' SEVERITY='WARNING']
      OUT
    end

    it "declares each inspection type once before its inspections" do
      expect(emit("teamcity")).to eq(service_messages)
    end

    it "groups a criterion's inspections across files under one type" do
      diagnostics = described_class.diagnostics("a.rb", [1], :line) + described_class.diagnostics("b.rb", [2], :line)

      expect(emit("teamcity", diagnostics).lines.grep(/inspectionType/).size).to eq(1)
    end

    it "escapes the service message syntax in a path" do
      diagnostics = described_class.diagnostics("it's|odd[1]\r\n.rb", [1], :line)

      expect(emit("teamcity", diagnostics)).to include("file='it|'s||odd|[1|]|r|n.rb'")
    end

    it "emits nothing for no diagnostics" do
      expect(emit("teamcity", [])).to be_empty
    end
  end

  describe "buildkite" do
    let(:markdown) do
      <<~OUT
        #### Not covered by tests
        - `lib/a.rb:41-43`
        - `lib/a.rb:47`

        #### Branch not covered by tests
        - `lib/a.rb:39`

        #### Method not covered by tests
        - `lib/b.rb:7`
      OUT
    end

    it "emits a Markdown section per message for buildkite-agent annotate" do
      expect(emit("buildkite")).to eq(markdown)
    end

    it "emits nothing for no diagnostics" do
      expect(emit("buildkite", [])).to be_empty
    end
  end
end
