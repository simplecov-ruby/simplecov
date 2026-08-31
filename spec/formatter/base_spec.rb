# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Formatter::Base do
  subject(:formatter) { described_class.new }

  let(:entry_point_formatter_class) do
    Class.new(described_class) do
    private

      def entry_point_filename
        "report.txt"
      end
    end
  end

  before { allow(SimpleCov::Color).to receive(:enabled?).and_return(false) }

  def statistics(covered, missed)
    SimpleCov::CoverageStatistics.new(covered: covered, missed: missed)
  end

  def result_with(coverage_statistics)
    instance_double(SimpleCov::Result, command_name: "RSpec", coverage_statistics: coverage_statistics)
  end

  it "writes its status only to stderr without engaging Warning.warn" do
    result = result_with(line: statistics(8, 2))
    allow(Warning).to receive(:warn).and_call_original
    stderr = nil
    stdout = capture_stdout do
      stderr = capture_stderr { formatter.send(:emit_status, result) }
    end

    expect(stderr).to include("Coverage report generated", "Line coverage: 8 / 10 (80.00%)")
    expect(stdout).to be_empty
    expect(Warning).not_to have_received(:warn)
  end

  it "loses the status line quietly when stderr was closed before at_exit (e.g. by rspec-conductor)" do
    result = result_with(line: statistics(8, 2))
    allow($stderr).to receive(:puts).and_raise(IOError, "closed stream")

    expect { formatter.send(:emit_status, result) }.not_to raise_error
  end

  it "does not build or emit a status when silent" do
    silent_formatter = described_class.new(silent: true)
    result = result_with(line: statistics(8, 2))
    allow(silent_formatter).to receive(:output_message)

    expect(capture_stderr { silent_formatter.send(:emit_status, result) }).to be_empty
    expect(silent_formatter).not_to have_received(:output_message)
  end

  it "prefixes nothing by default" do
    expect(formatter.send(:message_prefix)).to eq("")
  end

  it "lets a subclass mark the summary line" do
    marked = Class.new(described_class) do
    private

      def message_prefix
        "JSON "
      end
    end

    expect(marked.new.send(:output_message, result_with(line: statistics(8, 2)))).to eq(<<~TEXT.chomp)
      JSON Coverage report generated for RSpec to #{SimpleCov.coverage_dir}
      Line coverage: 8 / 10 (80.00%)
    TEXT
  end

  it "renders criterion lines on a subclass that defines its own format" do
    subclass = Class.new(described_class) do
      def format(_result)
        "report"
      end
    end

    expect(subclass.new.send(:output_message, result_with(line: statistics(8, 2))))
      .to end_with("Line coverage: 8 / 10 (80.00%)")
  end

  it "renders enabled criteria in result order with the Base defaults" do
    result = result_with(line: statistics(8, 2), branch: statistics(7, 3), method: statistics(9, 1))

    expect(formatter.send(:output_message, result)).to eq(<<~TEXT.chomp)
      Coverage report generated for RSpec to #{SimpleCov.coverage_dir}
      Line coverage: 8 / 10 (80.00%)
      Branch coverage: 7 / 10 (70.00%)
      Method coverage: 9 / 10 (90.00%)
    TEXT
  end

  it "renders the header alone for a run that measured no criteria" do
    expect(formatter.send(:output_message, result_with({})))
      .to eq("Coverage report generated for RSpec to #{SimpleCov.coverage_dir}")
  end

  it "keeps zero-total line coverage but omits zero-total optional criteria" do
    zero = statistics(0, 0)
    result = result_with(line: zero, branch: zero, method: zero)

    expect(formatter.send(:output_message, result)).to eq(<<~TEXT.chomp)
      Coverage report generated for RSpec to #{SimpleCov.coverage_dir}
      Line coverage: 0 / 0 (100.00%)
    TEXT
  end

  it "floors coverage instead of rounding it to 100 percent" do
    result = result_with(line: statistics(22_103, 1))

    expect(formatter.send(:output_message, result)).to end_with("Line coverage: 22103 / 22104 (99.99%)")
  end

  it "colorizes coverage when color output is enabled" do
    allow(SimpleCov::Color).to receive(:enabled?).and_return(true)
    result = result_with(line: statistics(8, 2))

    expect(formatter.send(:output_message, result)).to end_with("Line coverage: 8 / 10 (\e[33m80.00%\e[0m)")
  end

  it "appends a subclass entry point to an output directory inside cwd" do
    output_dir = File.join(Dir.pwd, "tmp", "formatter-base")
    formatter = entry_point_formatter_class.new(output_dir: output_dir)

    expect(formatter.send(:displayable_output_path)).to eq(File.join("tmp", "formatter-base", "report.txt"))
  end

  it "keeps an output directory outside cwd absolute" do
    Dir.mktmpdir do |output_dir|
      formatter = entry_point_formatter_class.new(output_dir: output_dir)
      expect(formatter.send(:displayable_output_path)).to eq(File.join(output_dir, "report.txt"))
    end
  end

  it "falls back to the configured path when paths cannot be relativized" do
    output_dir = File.join(Dir.pwd, "tmp", "formatter-base")
    formatter = entry_point_formatter_class.new(output_dir: output_dir)
    cwd = Pathname.pwd
    pathname = instance_double(Pathname)
    allow(Pathname).to receive(:new).with(output_dir).and_return(pathname)
    allow(Pathname).to receive(:pwd).and_return(cwd)
    allow(pathname).to receive(:relative_path_from).with(cwd).and_raise(ArgumentError)

    expect(formatter.send(:displayable_output_path)).to eq(File.join(output_dir, "report.txt"))
  end
end
