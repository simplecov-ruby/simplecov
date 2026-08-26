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

  it "accepts an array of run names as command_names" do
    data["meta"]["command_names"] = %w[result1 result2]
    expect(validate).to equal(data)
  end

  it "rejects a malformed command_names" do
    data["meta"]["command_names"] = "junk"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /command_names must be an array of strings/)
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

  # The production section is optional (a report without a configured
  # `production_coverage` store has none). When present the viewer
  # dereferences its files and their line lists, so those are checked.
  describe "production coverage" do
    let(:production) do
      {
        "started_at" => "2026-08-01T05:00:00Z",
        "updated_at" => "2026-08-25T11:00:00Z",
        "files" => {"lib/a.rb" => {"lines" => [1, 3], "last_seen" => "2026-08-25T10:00:00Z"}}
      }
    end

    before { data["production"] = production }

    it "accepts a document carrying a well-formed section" do
      expect(validate).to equal(data)
    end

    it "accepts a section without a window or stamps" do
      production.delete("started_at")
      production.delete("updated_at")
      production.dig("files", "lib/a.rb").delete("last_seen")
      expect(validate).to equal(data)
    end

    it "rejects a section that is not an object" do
      data["production"] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /"production" must be an object/)
    end

    it "rejects a section without a files table" do
      production.delete("files")
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /production\.files must be a hash/)
    end

    it "rejects a file entry whose lines are not positive integers" do
      production["files"]["lib/a.rb"] = {"lines" => [1, 0]}
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %r{production entry "lib/a\.rb" must list sorted line numbers})
    end

    it "rejects a file entry that is not an object" do
      production["files"]["lib/a.rb"] = [1, 3]
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %r{production entry "lib/a\.rb" must list sorted line numbers})
    end

    it "rejects a non-string stamp" do
      production["files"]["lib/a.rb"]["last_seen"] = 7
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %r{production entry "lib/a\.rb" last_seen must be a string})
    end
  end

  # The contexts data is optional (a report without `track_tests` has
  # none), but when present the viewer dereferences it, so its shape is
  # held to the same bar as the rest.
  describe "recorded contexts" do
    it "accepts a document carrying well-formed contexts" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "1"}
      expect(validate).to equal(data)
    end

    it "accepts their absence" do
      expect(validate).to equal(data)
    end

    it "rejects a non-array contexts list" do
      data["contexts"] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /"contexts" must be an array of strings/)
    end

    it "rejects non-string context ids" do
      data["contexts"] = ["spec/a_spec.rb:4", 7]
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /"contexts" must be an array of strings/)
    end

    it "rejects a wrong-shaped per-file bitmap table" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end

    it "rejects non-string bitmap values" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => 1}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end

    # The viewer converts each key with Number() and indexes the document's
    # context list with it, so the validator holds keys to exactly that
    # contract rather than letting the browser crash or render "undefined".
    it "rejects non-numeric bitmap keys" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"x" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end

    it "rejects bitmap keys that index no recorded context" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"1" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end

    it "rejects non-hex bitmap values" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "0xzz"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end

    it "rejects a bitmap table on a document with no context list" do
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, /must map recorded context indices/)
    end
  end
end
