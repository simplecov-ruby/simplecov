# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Formatter::HTMLFormatter::ViewerDataValidator do
  subject(:validate) { described_class.call(data) }

  let(:statistic) do
    {"covered" => 1, "missed" => 0, "total" => 1, "percent" => 100.0, "strength" => 1.0}
  end
  let(:context_error) do
    %(coverage entry "lib/a.rb" contexts must map recorded context indices to hex bitmaps)
  end
  let(:source_error) do
    %(coverage entry "lib/a.rb" must include an array of source strings; regenerate with source_in_json true)
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

  # Every refusal, each asserted as its whole message. The viewer
  # dereferences these sections without fallbacks, so a document that
  # gets past here has to carry exactly what it reads, and the message
  # is what tells someone regenerating a report which part is wrong.
  {
    ["meta", :section] => %("meta" must be an object),
    ["total", :section] => %("total" must be an object),
    ["coverage", :section] => %("coverage" must be an object),
    ["groups", :section] => %("groups" must be an object)
  }.each do |(key, _), message|
    it "rejects a #{key} section that is not an object" do
      data[key] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, message)
    end
  end

  {
    "simplecov_version" => "meta.simplecov_version must be a string",
    "command_name" => "meta.command_name must be a string",
    "project_name" => "meta.project_name must be a string",
    "timestamp" => "meta.timestamp must be a string"
  }.each do |key, message|
    it "rejects a non-string meta.#{key}" do
      data["meta"][key] = 1
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, message)
    end
  end

  %w[line_coverage branch_coverage method_coverage].each do |flag|
    it "rejects a non-boolean meta.#{flag}" do
      data["meta"][flag] = "yes"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.#{flag} must be a boolean")
    end
  end

  # Each criterion the metadata claims was measured must carry a full
  # set of numeric statistics, in the totals and in every group.
  %w[lines branches methods].each do |criterion|
    it "rejects a missing #{criterion} statistic" do
      data["total"][criterion] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "total.#{criterion} must be a hash")
    end
  end

  %w[covered missed total percent strength].each do |field|
    it "rejects a non-numeric #{field}" do
      data["total"]["lines"][field] = "x"
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, "total.lines.#{field} must be a numeric")
    end
  end

  it "names the group and the criterion a bad statistic belongs to" do
    data["groups"]["App"]["lines"] = "junk"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App".lines must be a hash))
  end

  it "names the group, criterion, and field of a non-numeric group statistic" do
    data["groups"]["App"]["lines"]["covered"] = "x"
    expect { validate }
      .to raise_error(SimpleCov::CoverageJSON::Error, %(group "App".lines.covered must be a numeric))
  end

  it "names the coverage entry that is not an object" do
    data["coverage"]["lib/a.rb"] = "junk"
    expect { validate }
      .to raise_error(SimpleCov::CoverageJSON::Error, %(coverage entry "lib/a.rb" must be an object))
  end

  # Source is what the viewer renders, so its absence is the one
  # refusal that says how to fix the report rather than what is wrong.
  it "tells a source-less report how to regenerate itself" do
    data["coverage"]["lib/a.rb"] = {"source" => "junk"}
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, source_error)
  end

  # A key the document never carries is as bad as one carrying junk:
  # the viewer dereferences it either way.
  it "rejects a document missing a section outright" do
    data.delete("groups")
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %("groups" must be an object))
  end

  it "rejects a coverage entry with no source at all" do
    data["coverage"]["lib/a.rb"] = {}
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, source_error)
  end

  it "rejects a group with no files list at all" do
    data["groups"]["App"].delete("files")
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App".files must be an array of strings))
  end

  it "rejects a group whose files are not a list" do
    data["groups"]["App"]["files"] = "lib/a.rb"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App".files must be an array of strings))
  end

  it "rejects a group that is an object of some other kind" do
    data["groups"]["App"] = "junk"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App" must be an object))
  end

  it "rejects meta with a coverage flag missing outright" do
    data["meta"].delete("branch_coverage")
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.branch_coverage must be a boolean")
  end

  # A criterion the run did not measure carries no statistics, and the
  # flags are what say which of them to expect.
  it "asks for statistics only where the metadata claims a measurement" do
    data["meta"]["method_coverage"] = false
    data["total"].delete("methods")
    data["groups"]["App"].delete("methods")

    expect(validate).to equal(data)
  end

  it "keeps checking the later criteria past one the run did not measure" do
    data["meta"]["line_coverage"] = false
    data["total"].delete("lines")
    data["groups"]["App"].delete("lines")
    data["total"]["branches"] = "junk"

    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "total.branches must be a hash")
  end

  it "accepts an array of run names as command_names" do
    data["meta"]["command_names"] = %w[result1 result2]
    expect(validate).to equal(data)
  end

  it "rejects a malformed command_names" do
    data["meta"]["command_names"] = "junk"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.command_names must be an array of strings")
  end

  it "rejects command_names carrying anything but strings" do
    data["meta"]["command_names"] = ["result1", 2]
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.command_names must be an array of strings")
  end

  it "rejects an invalid timestamp" do
    data.fetch("meta")["timestamp"] = "not-a-time"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.timestamp must be an ISO 8601 date-time")
  end

  it "rejects a non-boolean coverage flag" do
    data.fetch("meta")["branch_coverage"] = nil
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "meta.branch_coverage must be a boolean")
  end

  it "requires statistics for each enabled criterion" do
    data.fetch("total").delete("methods")
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "total.methods must be a hash")
  end

  it "requires numeric statistic fields" do
    data.dig("total", "lines")["covered"] = "one"
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "total.lines.covered must be a numeric")
  end

  it "requires every source entry to be a string" do
    data.dig("coverage", "lib/a.rb", "source") << 1
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, source_error)
  end

  it "requires every group to be an object" do
    data.fetch("groups")["App"] = nil
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App" must be an object))
  end

  it "requires every group filename to be a string" do
    data.dig("groups", "App", "files") << 1
    expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %(group "App".files must be an array of strings))
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
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %("production" must be an object))
    end

    it "rejects a section without a files table" do
      production.delete("files")
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, "production.files must be a hash")
    end

    it "rejects a file entry whose lines are not positive integers" do
      production["files"]["lib/a.rb"] = {"lines" => [1, 0]}
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" must list sorted line numbers))
    end

    it "rejects a file entry that is not an object" do
      production["files"]["lib/a.rb"] = [1, 3]
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" must list sorted line numbers))
    end

    it "rejects a file entry with no lines at all" do
      production["files"]["lib/a.rb"] = {"last_seen" => "2026-08-25T10:00:00Z"}
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" must list sorted line numbers))
    end

    it "rejects lines that are not a list" do
      production["files"]["lib/a.rb"] = {"lines" => "1,3"}
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" must list sorted line numbers))
    end

    it "rejects line numbers that are not numbers" do
      production["files"]["lib/a.rb"] = {"lines" => ["1"]}
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" must list sorted line numbers))
    end

    it "rejects a non-string stamp" do
      production["files"]["lib/a.rb"]["last_seen"] = 7
      expect { validate }
        .to raise_error(SimpleCov::CoverageJSON::Error, %(production entry "lib/a.rb" last_seen must be a string))
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
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %("contexts" must be an array of strings))
    end

    it "rejects non-string context ids" do
      data["contexts"] = ["spec/a_spec.rb:4", 7]
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, %("contexts" must be an array of strings))
    end

    it "rejects a wrong-shaped per-file bitmap table" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = "junk"
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    it "rejects non-string bitmap values" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => 1}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    # The viewer converts each key with Number() and indexes the document's
    # context list with it, so the validator holds keys to exactly that
    # contract rather than letting the browser crash or render "undefined".
    it "rejects non-numeric bitmap keys" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"x" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    it "rejects bitmap keys that index no recorded context" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"1" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    # Keys index the document's context list, so a project with more
    # than ten recorded contexts has keys longer than a digit, and
    # bitmaps are as long as the file they describe needs.
    it "accepts a multi-digit key and a multi-digit bitmap" do
      data["contexts"] = Array.new(11) { |index| "spec/a_spec.rb:#{index}" }
      data.dig("coverage", "lib/a.rb")["contexts"] = {"10" => "ff"}

      expect(validate).to equal(data)
    end

    it "rejects a table where only some entries are well formed" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "1", "x" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    it "rejects bitmap keys that are not strings" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {0 => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    it "rejects non-hex bitmap values" do
      data["contexts"] = ["spec/a_spec.rb:4"]
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "0xzz"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end

    it "rejects a bitmap table on a document with no context list" do
      data.dig("coverage", "lib/a.rb")["contexts"] = {"0" => "1"}
      expect { validate }.to raise_error(SimpleCov::CoverageJSON::Error, context_error)
    end
  end
end
