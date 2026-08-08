# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Formatter::HTMLFormatter::ViewerDataValidator do
  subject(:validate) { described_class.call(data) }

  let(:statistic) do
    {"covered" => 1, "missed" => 0, "total" => 1, "percent" => 100.0, "strength" => 1.0}
  end
  let(:data) do
    {
      "meta" => {
        "simplecov_version" => SimpleCov::VERSION,
        "command_name" => "RSpec",
        "project_name" => "Example",
        "timestamp" => Time.now.iso8601,
        "line_coverage" => true,
        "branch_coverage" => true,
        "method_coverage" => true
      },
      "total" => {
        "lines" => statistic.dup,
        "branches" => statistic.dup,
        "methods" => statistic.dup
      },
      "coverage" => {"lib/a.rb" => {"source" => ["puts :ok"]}},
      "groups" => {
        "App" => {
          "files" => ["lib/a.rb"],
          "lines" => statistic.dup,
          "branches" => statistic.dup,
          "methods" => statistic.dup
        }
      }
    }
  end

  it "returns a usable viewer document unchanged" do
    expect(validate).to equal(data)
  end

  it "rejects an invalid timestamp" do
    data.fetch("meta")["timestamp"] = "not-a-time"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /ISO 8601/)
  end

  it "rejects a non-boolean coverage flag" do
    data.fetch("meta")["branch_coverage"] = nil
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /branch_coverage must be a boolean/)
  end

  it "requires statistics for each enabled criterion" do
    data.fetch("total").delete("methods")
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /total\.methods must be a hash/)
  end

  it "requires numeric statistic fields" do
    data.dig("total", "lines")["covered"] = "one"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /total\.lines\.covered must be a numeric/)
  end

  it "requires every source entry to be a string" do
    data.dig("coverage", "lib/a.rb", "source") << 1
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /array of source strings/)
  end

  it "requires every group to be an object" do
    data.fetch("groups")["App"] = nil
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /group "App" must be an object/)
  end

  it "requires every group filename to be a string" do
    data.dig("groups", "App", "files") << 1
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /files must be an array of strings/)
  end
end
