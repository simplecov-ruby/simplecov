# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Formatter::SimpleFormatter do
  subject(:formatter) { described_class.new }

  let(:source_file) { instance_double(SimpleCov::SourceFile, filename: "lib/example.rb") }
  let(:result) { instance_double(SimpleCov::Result, groups: {"Demo" => [source_file]}) }
  let(:branch_report) do
    <<~TEXT
      Group: Demo
      ========================================
      lib/example.rb (coverage: 50.12%)

    TEXT
  end

  it "prints each file's primary coverage percentage" do
    allow(SimpleCov).to receive(:primary_coverage).and_return(:branch)
    allow(source_file).to receive(:covered_percent).with(:branch).and_return(50.129)

    expect(formatter.format(result)).to eq(branch_report)
  end

  it "normalizes oneshot-line coverage to line statistics" do
    allow(SimpleCov).to receive(:primary_coverage).and_return(:oneshot_line)
    allow(source_file).to receive(:covered_percent).with(:line).and_return(75.559)

    expect(formatter.format(result)).to include("lib/example.rb (coverage: 75.55%)")
  end
end
