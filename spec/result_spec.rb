# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Result do
  context "with a (mocked) Coverage.result" do
    around do |example|
      prev_filters   = SimpleCov.filters
      prev_groups    = SimpleCov.groups
      prev_formatter = SimpleCov.formatter

      SimpleCov.filters   = []
      SimpleCov.groups    = {}
      SimpleCov.formatter = nil

      example.run

      SimpleCov.filters   = prev_filters
      SimpleCov.groups    = prev_groups
      SimpleCov.formatter = prev_formatter
    end

    let(:original_result) do
      {
        source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]},
        source_fixture("app/models/user.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]},
        source_fixture("app/controllers/sample_controller.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil]}
      }
    end

    context "when a simple cov result initialized from that" do
      subject(:result) { described_class.new(original_result) }

      it "has 3 filenames" do
        expect(result.filenames.count).to eq(3)
      end

      it "has 3 source files" do
        expect(result.source_files.count).to eq(3)
        expect(result.source_files).to all(be_a SimpleCov::SourceFile)
      end

      it "returns an instance of SimpleCov::FileList for source_files and files" do
        expect(result.files).to be_a SimpleCov::FileList
        expect(result.source_files).to be_a SimpleCov::FileList
      end

      it "has files equal to source_files" do
        expect(result.files).to eq(result.source_files)
      end

      it "has accurate covered percent" do
        # in our fixture, there are 13 covered line (result in 1) in all 15 relevant line (result in non-nil)
        expect(result.covered_percent).to eq(86.66666666666667)
      end

      it "has accurate covered percentages" do
        expect(result.covered_percentages).to eq([80.0, 80.0, 100.0])
      end

      it "has accurate least covered file" do
        expect(result.least_covered_file).to match(/sample_controller.rb/)
      end

      delegated_messages = %i[
        covered_percent covered_percentages least_covered_file covered_strength
        covered_lines missed_lines total_lines
      ]
      delegated_messages.each do |msg|
        it "responds to #{msg}" do
          expect(result).to respond_to(msg)
        end
      end

      context "when dumped with to_hash" do
        it "is a hash" do
          expect(result.to_hash).to be_a Hash
        end

        context "when loaded back with from_hash" do
          let(:dumped_result) do
            described_class.from_hash(result.to_hash).first
          end

          it "has 3 source files" do
            expect(dumped_result.source_files.count).to eq(result.source_files.count)
          end

          it "has the same covered_percent" do
            expect(dumped_result.covered_percent).to eq(result.covered_percent)
          end

          it "has the same covered_percentages" do
            expect(dumped_result.covered_percentages).to eq(result.covered_percentages)
          end

          it "has the same timestamp" do
            expect(dumped_result.created_at.to_i).to eq(result.created_at.to_i)
          end

          it "has the same command_name" do
            expect(dumped_result.command_name).to eq(result.command_name)
          end

          it "has the same original_result" do
            expect(dumped_result.original_result).to eq(result.original_result)
          end
        end
      end
    end

    context "with some filters set up" do
      before do
        SimpleCov.add_filter "sample.rb"
      end

      it "has 2 files in a new simple cov result" do
        expect(described_class.new(original_result).source_files.length).to eq(2)
      end

      it "has 80 covered percent" do
        expect(described_class.new(original_result).covered_percent).to eq(80)
      end

      it "has [80.0, 80.0] covered percentages" do
        expect(described_class.new(original_result).covered_percentages).to eq([80.0, 80.0])
      end

      it "ignores the global filter chain when filters: [] is passed" do
        result = described_class.new(original_result, filters: [])
        expect(result.source_files.length).to eq(3)
      end

      it "uses the explicitly-passed filters instead of the singleton's" do
        explicit_filter = SimpleCov::StringFilter.new("user.rb")
        result = described_class.new(original_result, filters: [explicit_filter])
        # Drops user.rb, keeps sample.rb (which the global chain would have filtered)
        expect(result.filenames.map { |f| File.basename(f) }).to contain_exactly(
          "sample.rb",
          "sample_controller.rb"
        )
      end
    end

    context "with groups set up for all files" do
      subject(:result) do
        described_class.new(original_result)
      end

      before do
        SimpleCov.add_group "Models", "app/models"
        SimpleCov.add_group "Controllers", ["app/controllers"]
        SimpleCov.add_group "Other" do |src_file|
          File.basename(src_file.filename) == "sample.rb"
        end
      end

      it "has 3 groups" do
        expect(result.groups.length).to eq(3)
      end

      it "has user.rb in 'Models' group" do
        expect(File.basename(result.groups["Models"].first.filename)).to eq("user.rb")
      end

      it "has sample_controller.rb in 'Controllers' group" do
        expect(File.basename(result.groups["Controllers"].first.filename)).to eq("sample_controller.rb")
      end

      context "when simple formatter being used" do
        before do
          SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter
        end

        it "returns a formatted string with result.format!" do
          expect(result.format!).to be_a String
        end
      end

      context "when multi formatter being used" do
        before do
          SimpleCov.formatters = [
            SimpleCov::Formatter::SimpleFormatter,
            SimpleCov::Formatter::SimpleFormatter
          ]
        end

        it "returns an array containing formatted string with result.format!" do
          formatted = result.format!
          expect(formatted.count).to eq(2)
          expect(formatted.first).to be_a String
        end
      end
    end

    context "with groups set up that do not match all files" do
      subject(:result) { described_class.new(original_result) }

      before do
        SimpleCov.configure do
          add_group "Models", "app/models"
          add_group "Controllers", "app/controllers"
        end
      end

      it "has 3 groups" do
        expect(result.groups.length).to eq(3)
      end

      it "has 1 item per group" do
        result.groups.each_value do |files|
          expect(files.length).to eq(1)
        end
      end

      it 'has sample.rb in "Ungrouped" group' do
        expect(File.basename(result.groups["Ungrouped"].first.filename)).to eq("sample.rb")
      end

      it "returns all groups as instances of SimpleCov::FileList" do
        result.groups.each_value do |files|
          expect(files).to be_a SimpleCov::FileList
        end
      end
    end

    describe ".from_hash" do
      let(:other_result) do
        {
          source_fixture("sample.rb") => {"lines" => [nil, 1, 1, 1, nil, nil, 0, 0, nil, nil]}
        }
      end
      let(:created_at) { Time.now.to_i }

      it "can consume multiple commands" do
        input = {
          "rspec" => {
            "coverage" => original_result,
            "timestamp" => created_at
          },
          "cucumber" => {
            "coverage" => other_result,
            "timestamp" => created_at
          }
        }

        result = described_class.from_hash(input)

        expect(result.size).to eq 2
        sorted = result.sort_by(&:command_name)
        expect(sorted.map(&:command_name)).to eq %w[cucumber rspec]
        expect(sorted.map { |r| r.created_at.to_i }).to eq [created_at, created_at]
        expect(sorted.map(&:original_result)).to eq [other_result, original_result]
      end
    end

    describe "#source_file_for and #coverage_for" do
      subject(:result) { described_class.new(original_result) }

      let(:user_path) { source_fixture("app/models/user.rb") }

      it "looks up by absolute path" do
        expect(result.source_file_for(user_path).filename).to eq(user_path)
      end

      it "looks up by path relative to SimpleCov.root" do
        relative = Pathname.new(user_path).relative_path_from(Pathname.new(SimpleCov.root)).to_s
        expect(result.source_file_for(relative).filename).to eq(user_path)
      end

      it "returns nil for an unknown path" do
        expect(result.source_file_for("does/not/exist.rb")).to be_nil
        expect(result.coverage_for("does/not/exist.rb")).to be_nil
      end

      it "returns the per-criterion coverage_statistics for a known file" do
        stats = result.coverage_for(user_path)
        expect(stats[:line]).to be_a(SimpleCov::CoverageStatistics)
        expect(stats[:line].covered).to be_positive
      end
    end

    # Regression for https://github.com/simplecov-ruby/simplecov/issues/980.
    # When a resultset references source files that don't exist locally,
    # the silent "0 / 0 (100.00%)" outcome looks like success. Result now
    # emits a single summary warning naming the missing paths.
    describe "warning when resultset paths don't exist on this filesystem" do
      let(:missing_only) do
        {
          "/does/not/exist/foo.rb" => {"lines" => [1, nil, 0]},
          "/also/missing/bar.rb" => {"lines" => [1, 1, nil]}
        }
      end

      it "emits a louder warning when every source file is missing (the collate-across-machines case)" do
        stderr = capture_stderr { described_class.new(missing_only) }
        expect(stderr).to include("dropped all 2 source file(s)")
        expect(stderr).to include("/does/not/exist/foo.rb")
        expect(stderr).to include("/also/missing/bar.rb")
        expect(stderr).to include("SimpleCov.collate")
      end

      it "emits a quieter warning when some-but-not-all source files are missing" do
        partial = original_result.merge("/does/not/exist/foo.rb" => {"lines" => [1, nil]})
        stderr = capture_stderr { described_class.new(partial) }
        expect(stderr).to include("dropped 1 source file(s)")
        expect(stderr).to include("/does/not/exist/foo.rb")
        expect(stderr).not_to include("SimpleCov.collate")
      end

      it "doesn't warn when every source file is present" do
        stderr = capture_stderr { described_class.new(original_result) }
        expect(stderr).to be_empty
      end

      it "caps the listed paths at five with a `+N more` suffix" do
        many_missing = (1..8).to_h { |n| ["/missing/file#{n}.rb", {"lines" => [1]}] }
        stderr = capture_stderr { described_class.new(many_missing) }
        expect(stderr).to include("(+3 more)")
      end
    end
  end
end
