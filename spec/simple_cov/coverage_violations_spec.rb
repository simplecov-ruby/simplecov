# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::CoverageViolations, mutant_expression: "SimpleCov::CoverageViolations*" do
  def line_stats = SimpleCov::CoverageStatistics.new(covered: 80, missed: 20)

  def branch_stats = SimpleCov::CoverageStatistics.new(covered: 5, missed: 5)

  describe ".minimum_overall" do
    it "reports violations for criteria below threshold" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats, branch: branch_stats})
      violations = described_class.minimum_overall(result, line: 90)
      expect(violations).to contain_exactly(criterion: :line, expected: 90, actual: 80.0)
    end

    it "skips a configured threshold whose criterion isn't in the stats" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats})
      violations = described_class.minimum_overall(result, line: 100, branch: 100)
      expect(violations).to contain_exactly(criterion: :line, expected: 100, actual: 80.0)
    end
  end

  describe ".minimum_by_file" do
    let(:file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/a.rb",
        project_filename: "lib/a.rb",
        coverage_statistics: {line: line_stats})
    end

    it "skips a configured threshold whose criterion isn't in the file's stats" do
      result = instance_double(SimpleCov::Result, files: [file])
      violations = described_class.minimum_by_file(result, {line: 100, branch: 100})
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end
  end

  describe ".maximum_drop baselines" do
    let(:result) { instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats}) }

    def entry(branch, line_percent)
      {"branch" => branch, "totals" => {"line" => line_percent}}
    end

    context "with drop_baseline :median" do
      it "measures the drop against the history's per-criterion median" do
        allow(SimpleCov::History).to receive(:read)
          .and_return([entry("main", 90.0), entry("main", 100.0), entry("main", 80.0)])

        violations = described_class.maximum_drop(result, {line: 5}, mode: :median)
        expect(violations).to contain_exactly(criterion: :line, maximum: 5, actual: 10.0)
      end

      it "averages the middle pair for an even run count" do
        allow(SimpleCov::History).to receive(:read)
          .and_return([entry("main", 90.0), entry("main", 100.0)])

        violations = described_class.maximum_drop(result, {line: 5}, mode: :median)
        expect(violations).to contain_exactly(criterion: :line, maximum: 5, actual: 15.0)
      end

      it "finds nothing to compare against in an empty history" do
        allow(SimpleCov::History).to receive(:read).and_return([])

        expect(described_class.maximum_drop(result, {line: 0}, mode: :median)).to eq([])
      end

      it "medians over the well-formed entries, skipping hand-edited debris" do
        allow(SimpleCov::History).to receive(:read)
          .and_return(["debris", {"totals" => nil}, entry("main", 90.0)])

        violations = described_class.maximum_drop(result, {line: 5}, mode: :median)
        expect(violations).to contain_exactly(criterion: :line, maximum: 5, actual: 10.0)
      end
    end

    context "with drop_baseline :branch" do
      before { allow(SimpleCov::History).to receive(:git_info).and_return(%w[feature abc]) }

      it "measures against the newest recorded run on the current branch" do
        allow(SimpleCov::History).to receive(:read)
          .and_return([entry("feature", 95.0), entry("main", 100.0), entry("feature", 90.0)])

        violations = described_class.maximum_drop(result, {line: 5}, mode: :branch)
        expect(violations).to contain_exactly(criterion: :line, maximum: 5, actual: 10.0)
      end

      it "finds nothing to compare against when the branch has no recorded run" do
        allow(SimpleCov::History).to receive(:read).and_return([entry("main", 100.0)])

        expect(described_class.maximum_drop(result, {line: 0}, mode: :branch)).to eq([])
      end

      it "finds nothing to compare against outside a branch (detached HEAD, no git)" do
        allow(SimpleCov::History).to receive(:git_info).and_return([nil, nil])

        expect(described_class.maximum_drop(result, {line: 0}, mode: :branch)).to eq([])
      end
    end
  end

  describe ".minimum_by_group" do
    let(:group) { instance_double(SimpleCov::FileList, coverage_statistics: {line: line_stats}) }

    it "skips a configured threshold whose criterion isn't in the group's stats" do
      result = instance_double(SimpleCov::Result, groups: {"Models" => group})
      violations = described_class.minimum_by_group(result, "Models" => {line: 100, branch: 100})
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end

    it "names the group, criterion, and both percents in the violation" do
      result = instance_double(SimpleCov::Result, groups: {"Models" => group})
      expect(described_class.minimum_by_group(result, "Models" => {line: 90}))
        .to eq([{group_name: "Models", criterion: :line, expected: 90, actual: 80.0}])
    end
  end

  describe "violation shapes" do
    let(:file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/a.rb",
        project_filename: "lib/a.rb",
        coverage_statistics: {line: line_stats, branch: branch_stats})
    end
    let(:result) { instance_double(SimpleCov::Result, files: [file]) }
    let(:totals) { instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats}) }
    let(:path_aware_baseline) do
      instance_double(SimpleCov::Baseline).tap do |baseline|
        allow(baseline).to receive(:covers?).with("lib/a.rb", :line).and_return(true)
        allow(baseline).to receive(:covers?).with("lib/a.rb", :branch).and_return(false)
      end
    end

    it "carries both filenames and both percents in a per-file minimum violation" do
      expect(described_class.minimum_by_file(result, {line: 90}))
        .to eq([{criterion: :line, expected: 90, actual: 80.0,
                 filename: "/abs/lib/a.rb", project_filename: "lib/a.rb"}])
    end

    it "carries both filenames and both counts in a per-file missed-cap violation" do
      expect(described_class.maximum_missed_by_file(result, {line: 5}))
        .to eq([{criterion: :line, maximum: 5, actual: 20,
                 filename: "/abs/lib/a.rb", project_filename: "lib/a.rb"}])
    end

    it "keeps checking the overall minimums that follow an unmeasured criterion" do
      expect(described_class.minimum_overall(totals, branch: 100, line: 90))
        .to eq([{criterion: :line, expected: 90, actual: 80.0}])
    end

    it "keeps checking the overall maximums that follow an unmeasured criterion" do
      expect(described_class.maximum_overall(totals, branch: 0, line: 70))
        .to eq([{criterion: :line, expected: 70, actual: 80.0}])
    end

    it "keeps checking the overall missed caps that follow an unmeasured criterion" do
      expect(described_class.maximum_missed(totals, branch: 0, line: 5))
        .to eq([{criterion: :line, maximum: 5, actual: 20}])
    end

    it "keeps checking the per-file minimums that follow an unmeasured criterion" do
      expect(described_class.minimum_by_file(result, {method: 100, line: 90}).map { |v| v[:criterion] })
        .to eq([:line])
    end

    it "keeps checking the per-file missed caps that follow an unmeasured criterion" do
      expect(described_class.maximum_missed_by_file(result, {method: 0, line: 5}).map { |v| v[:criterion] })
        .to eq([:line])
    end

    it "looks up a oneshot line minimum in the line bucket it folds into" do
      expect(described_class.minimum_overall(totals, oneshot_line: 90))
        .to eq([{criterion: :oneshot_line, expected: 90, actual: 80.0}])
    end

    it "looks up a oneshot line missed cap in the line bucket it folds into" do
      expect(described_class.maximum_missed(totals, oneshot_line: 5))
        .to eq([{criterion: :oneshot_line, maximum: 5, actual: 20}])
    end

    it "reports the overall minimum violation with its own percent" do
      expect(described_class.minimum_overall(totals, line: 90))
        .to eq([{criterion: :line, expected: 90, actual: 80.0}])
    end

    it "reports the overall maximum violation with its own percent" do
      expect(described_class.maximum_overall(totals, line: 70))
        .to eq([{criterion: :line, expected: 70, actual: 80.0}])
    end

    it "reports the overall missed-cap violation with its own count" do
      expect(described_class.maximum_missed(totals, line: 5))
        .to eq([{criterion: :line, maximum: 5, actual: 20}])
    end

    it "asks the baseline about this file's own path for a per-file minimum" do
      expect(described_class.minimum_by_file(result, {line: 100, branch: 100}, baseline: path_aware_baseline)
                            .map { |violation| violation[:criterion] }).to eq([:branch])
    end

    it "asks the baseline about this file's own path for a per-file missed cap" do
      expect(described_class.maximum_missed_by_file(result, {line: 0, branch: 0}, baseline: path_aware_baseline)
                            .map { |violation| violation[:criterion] }).to eq([:branch])
    end

    it "keeps checking later criteria after a baseline-exempt one" do
      baseline = instance_double(SimpleCov::Baseline)
      allow(baseline).to receive(:covers?).and_return(true, false)

      expect(described_class.minimum_by_file(result, {line: 100, branch: 100}, baseline: baseline).size).to eq(1)
    end
  end

  describe ".baseline" do
    let(:floor) { SimpleCov::Baseline::Floor.new(percent: 90.0, missed: nil) }
    let(:file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/a.rb",
        project_filename: "lib/a.rb",
        coverage_statistics: {line: line_stats})
    end
    let(:result) { instance_double(SimpleCov::Result, files: [file]) }
    let(:uneven_file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/b.rb", project_filename: "lib/b.rb",
        coverage_statistics: {line: SimpleCov::CoverageStatistics.new(covered: 1, missed: 2)})
    end
    let(:other_file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/z.rb", project_filename: "lib/z.rb",
        coverage_statistics: {line: line_stats})
    end

    def baseline_for(entry)
      instance_double(SimpleCov::Baseline).tap do |double|
        allow(double).to receive(:entry_for).with("lib/a.rb").and_return(entry)
      end
    end

    it "finds nothing to enforce without a baseline at all" do
      expect(described_class.baseline(result, nil)).to eq([])
    end

    it "skips a file the baseline has no entry for" do
      expect(described_class.baseline(result, baseline_for(nil))).to eq([])
    end

    it "reports a file below its floor with both filenames and both axes" do
      expect(described_class.baseline(result, baseline_for(line: floor)))
        .to eq([{criterion: :line, expected: 90.0, allowed_missed: nil, actual: 80.0, actual_missed: 20,
                 filename: "/abs/lib/a.rb", project_filename: "lib/a.rb"}])
    end

    it "skips a criterion the floor records but the run never measured" do
      expect(described_class.baseline(result, baseline_for(branch: floor))).to eq([])
    end

    it "forgives a percent dip the floor's own miss count still allows" do
      forgiving = SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 20)
      expect(described_class.baseline(result, baseline_for(line: forgiving))).to eq([])
    end

    it "reports a file that broke through both axes of its floor" do
      strict = SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 19)
      expect(described_class.baseline(result, baseline_for(line: strict)).size).to eq(1)
    end

    it "forgives a file that is exactly at its floor" do
      exact = SimpleCov::Baseline::Floor.new(percent: 80.0, missed: nil)
      expect(described_class.baseline(result, baseline_for(line: exact))).to eq([])
    end

    it "forgives a file with fewer misses than its floor allows" do
      generous = SimpleCov::Baseline::Floor.new(percent: 90.0, missed: 25)
      expect(described_class.baseline(result, baseline_for(line: generous))).to eq([])
    end

    it "rounds the percent it reports the way every other check does" do
      baseline = instance_double(SimpleCov::Baseline)
      allow(baseline).to receive(:entry_for).with("lib/b.rb").and_return(line: floor)
      uneven = instance_double(SimpleCov::Result, files: [uneven_file])

      expect(described_class.baseline(uneven, baseline).first[:actual]).to eq(33.33)
    end

    it "reads a oneshot line floor against the line bucket it folds into" do
      floor = SimpleCov::Baseline::Floor.new(percent: 90.0, missed: nil)
      expect(described_class.baseline(result, baseline_for(oneshot_line: floor)).map { |v| v[:criterion] })
        .to eq([:oneshot_line])
    end

    it "keeps checking the files that follow one the baseline has no entry for" do
      baseline = instance_double(SimpleCov::Baseline)
      allow(baseline).to receive(:entry_for).with("lib/a.rb").and_return(nil)
      allow(baseline).to receive(:entry_for).with("lib/z.rb").and_return(line: floor)
      pair = instance_double(SimpleCov::Result, files: [file, other_file])

      expect(described_class.baseline(pair, baseline).map { |v| v[:project_filename] }).to eq(["lib/z.rb"])
    end
  end

  describe ".maximum_drop" do
    it "skips a configured drop check whose criterion isn't in the stats" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats})
      last_run = {result: {line: 90.0, branch: 90.0}}
      violations = described_class.maximum_drop(result, {line: 5, branch: 5}, last_run: last_run)
      expect(violations.map { |v| v[:criterion] }).to contain_exactly(:line)
    end

    it "treats a non-numeric last-run value as missing instead of raising" do
      result = instance_double(SimpleCov::Result, coverage_statistics: {line: line_stats})
      violations = described_class.maximum_drop(result, {line: 5}, last_run: {result: {line: "95.0"}})
      expect(violations).to eq([])
    end
  end

  describe "drop baselines" do
    let(:method_stats) { SimpleCov::CoverageStatistics.new(covered: 3, missed: 7) }
    let(:result) do
      instance_double(SimpleCov::Result,
        coverage_statistics: {line: line_stats, branch: branch_stats, method: method_stats})
    end
    let(:hashlike) { Class.new(Hash) }

    def drop(thresholds, **options)
      described_class.maximum_drop(result, thresholds, **options)
    end

    context "with the last run" do
      it "measures the drop against the recorded percent" do
        expect(drop({line: 5}, last_run: {result: {line: 95.0}}))
          .to eq([{criterion: :line, maximum: 5, actual: 15.0}])
      end

      it "reads the pre-criteria file format's spelling of the line percent" do
        expect(drop({line: 5}, last_run: {result: {covered_percent: 95.0}}))
          .to eq([{criterion: :line, maximum: 5, actual: 15.0}])
      end

      it "prefers the criterion-keyed percent over the legacy spelling" do
        expect(drop({line: 5}, last_run: {result: {line: 95.0, covered_percent: 100.0}}))
          .to eq([{criterion: :line, maximum: 5, actual: 15.0}])
      end

      it "measures each criterion against its own recorded percent" do
        expect(drop({branch: 5}, last_run: {result: {line: 100.0, branch: 90.0}}))
          .to eq([{criterion: :branch, maximum: 5, actual: 40.0}])
      end

      it "reads a Hash subclass the way it reads a Hash" do
        last_run = hashlike.new.merge!(result: hashlike.new.merge!(line: 95.0))
        expect(drop({line: 5}, last_run: last_run)).to eq([{criterion: :line, maximum: 5, actual: 15.0}])
      end

      it "treats a run with no result at all as nothing to compare against" do
        expect(drop({line: 0}, last_run: {})).to eq([])
      end

      it "treats a result of debris as nothing to compare against" do
        expect(drop({line: 0}, last_run: {result: "debris"})).to eq([])
      end

      it "treats a whole file of debris as nothing to compare against" do
        allow(SimpleCov::LastRun).to receive(:read).and_return("debris")
        expect(drop({line: 0})).to eq([])
      end

      it "reads .last_run.json itself when no run is passed in" do
        allow(SimpleCov::LastRun).to receive(:read).and_return(result: {line: 95.0})
        expect(drop({line: 5})).to eq([{criterion: :line, maximum: 5, actual: 15.0}])
      end

      it "stays quiet about a criterion the recorded run never carried" do
        expect(drop({branch: 0}, last_run: {result: {line: 95.0}})).to eq([])
      end

      it "allows a drop exactly at the maximum" do
        expect(drop({line: 5}, last_run: {result: {line: 85.0}})).to eq([])
      end

      it "carries the method percent the recorded run kept" do
        expect(drop({method: 5}, last_run: {result: {line: 100.0, method: 90.0}}))
          .to eq([{criterion: :method, maximum: 5, actual: 60.0}])
      end

      it "treats a run with no percents at all as nothing to compare against" do
        expect(drop({line: 0, branch: 0, method: 0}, last_run: {result: {}})).to eq([])
      end

      it "measures a oneshot line drop against the line percent it folds into" do
        expect(drop({oneshot_line: 5}, last_run: {result: {line: 95.0}}))
          .to eq([{criterion: :oneshot_line, maximum: 5, actual: 15.0}])
      end

      it "rounds away a drop past the tenth decimal place" do
        expect(drop({line: -1}, last_run: {result: {line: 80.00000000009}}))
          .to eq([{criterion: :line, maximum: -1, actual: 0.0}])
      end

      it "keeps a drop at the tenth decimal place" do
        expect(drop({line: -1}, last_run: {result: {line: 80.0000000009}}))
          .to eq([{criterion: :line, maximum: -1, actual: 9.0e-10}])
      end

      it "follows the configured drop_baseline when the caller names no mode" do
        allow(SimpleCov).to receive(:drop_baseline).and_return(:median)
        allow(SimpleCov::History).to receive(:read).and_return([{"totals" => {"line" => 90.0}}])
        allow(SimpleCov::LastRun).to receive(:read).and_return(result: {line: 100.0})

        expect(drop({line: 5})).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end
    end

    context "with the history median" do
      def history(*entries)
        allow(SimpleCov::History).to receive(:read).and_return(entries)
      end

      it "medians each criterion over its own recorded values" do
        history({"totals" => {"line" => 90.0, "branch" => 70.0}},
          {"totals" => {"line" => 100.0, "branch" => 60.0}}, {"totals" => {"line" => 80.0, "branch" => 80.0}})

        expect(drop({line: 5, branch: 5}, mode: :median))
          .to contain_exactly({criterion: :line, maximum: 5, actual: 10.0}, {criterion: :branch, maximum: 5, actual: 20.0})
      end

      it "medians a criterion recorded in only some runs" do
        history({"totals" => {"line" => 90.0}}, {"totals" => {"line" => 100.0, "branch" => 90.0}})
        expect(drop({branch: 5}, mode: :median)).to eq([{criterion: :branch, maximum: 5, actual: 40.0}])
      end

      it "ignores a non-numeric recorded percent rather than sorting it against numbers" do
        history({"totals" => {"line" => "debris"}}, {"totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :median)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "finds nothing to compare against when no run recorded any numeric total" do
        history({"totals" => {"line" => "debris"}})
        expect(drop({line: 0}, mode: :median)).to eq([])
      end

      it "reads history entries and their totals as Hash subclasses" do
        history(hashlike.new.merge!("totals" => hashlike.new.merge!("line" => 90.0)))
        expect(drop({line: 5}, mode: :median)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips an entry with no totals key at all" do
        history({"branch" => "main"}, {"totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :median)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips an entry whose totals are the wrong shape entirely" do
        history({"totals" => 42}, {"totals" => ["line"]}, {"totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :median)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips a truthy entry that is not a Hash at all" do
        history(["totals"], {"totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :median)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "medians the middle pair of an even run count, not the pair below it" do
        history({"totals" => {"line" => 10.0}}, {"totals" => {"line" => 20.0}},
          {"totals" => {"line" => 30.0}}, {"totals" => {"line" => 40.0}})
        expect(drop({line: -100}, mode: :median)).to eq([{criterion: :line, maximum: -100, actual: -55.0}])
      end

      it "medians the method percents too" do
        history({"totals" => {"method" => 90.0}}, {"totals" => {"method" => 100.0}}, {"totals" => {"method" => 80.0}})
        expect(drop({method: 5}, mode: :median)).to eq([{criterion: :method, maximum: 5, actual: 60.0}])
      end
    end

    context "with the current branch" do
      before { allow(SimpleCov::History).to receive(:git_info).and_return(%w[feature abc]) }

      def history(*entries)
        allow(SimpleCov::History).to receive(:read).and_return(entries)
      end

      it "carries every criterion the branch's newest run recorded" do
        history({"branch" => "feature", "totals" => {"line" => 90.0, "branch" => 90.0}})
        expect(drop({line: 5, branch: 5}, mode: :branch))
          .to contain_exactly({criterion: :line, maximum: 5, actual: 10.0},
            {criterion: :branch, maximum: 5, actual: 40.0})
      end

      it "skips an entry recorded on another branch" do
        history({"branch" => "feature", "totals" => {"line" => 90.0}},
          {"branch" => "main", "totals" => {"line" => 100.0}})
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips an entry with no branch key at all" do
        history({"branch" => "feature", "totals" => {"line" => 90.0}}, {"totals" => {"line" => 100.0}})
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips a branch entry whose totals are debris" do
        history({"branch" => "feature", "totals" => {"line" => 90.0}}, {"branch" => "feature", "totals" => "debris"})
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips debris where an entry should be" do
        history("debris", {"branch" => "feature", "totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "reads a branch entry and its totals as Hash subclasses" do
        history(hashlike.new.merge!("branch" => "feature", "totals" => hashlike.new.merge!("line" => 90.0)))
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "skips a truthy entry that is not a Hash at all" do
        history(["feature"], {"branch" => "feature", "totals" => {"line" => 90.0}})
        expect(drop({line: 5}, mode: :branch)).to eq([{criterion: :line, maximum: 5, actual: 10.0}])
      end

      it "carries every criterion the entry recorded, method included" do
        history({"branch" => "feature", "totals" => {"method" => 90.0}})
        expect(drop({method: 5}, mode: :branch)).to eq([{criterion: :method, maximum: 5, actual: 60.0}])
      end

      it "ignores a branchless entry rather than matching it to the current branch" do
        history({"totals" => {"line" => 90.0}})
        expect(drop({line: 0}, mode: :branch)).to eq([])
      end

      it "compares against nothing outside a branch, even with branchless entries recorded" do
        allow(SimpleCov::History).to receive(:git_info).and_return([nil, nil])
        history({"branch" => nil, "totals" => {"line" => 90.0}})
        expect(drop({line: 0}, mode: :branch)).to eq([])
      end
    end
  end

  describe ".minimum_by_file overrides" do
    let(:two_criterion_file) do
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/lib/a.rb", project_filename: "lib/a.rb",
        coverage_statistics: {line: line_stats, branch: branch_stats})
    end

    def file_double(project_filename)
      instance_double(SimpleCov::SourceFile,
        filename: "/abs/#{project_filename}",
        project_filename: project_filename,
        coverage_statistics: {line: line_stats})
    end

    def thresholds_for(project_filename, overrides)
      result = instance_double(SimpleCov::Result, files: [file_double(project_filename)])
      described_class.minimum_by_file(result, {line: 0}, overrides).map { |violation| violation[:expected] }
    end

    it "applies a Regexp override to the paths it matches" do
      expect(thresholds_for("lib/a.rb", /a\.rb\z/ => {line: 90})).to eq([90])
    end

    it "leaves a path the Regexp override misses on the default" do
      expect(thresholds_for("lib/b.rb", /a\.rb\z/ => {line: 90})).to eq([])
    end

    it "treats a trailing slash as a directory prefix" do
      expect(thresholds_for("lib/deep/a.rb", "lib/" => {line: 90})).to eq([90])
    end

    it "leaves a path outside the directory prefix on the default" do
      expect(thresholds_for("app/a.rb", "lib/" => {line: 90})).to eq([])
    end

    it "matches a bare String exactly" do
      expect(thresholds_for("lib/a.rb", "lib/a.rb" => {line: 90})).to eq([90])
    end

    it "does not match a bare String as a filename prefix" do
      expect(thresholds_for("lib/a.rb.bak", "lib/a.rb" => {line: 90})).to eq([])
    end

    it "does not match a bare String as a directory prefix" do
      expect(thresholds_for("lib/a.rb", "lib" => {line: 90})).to eq([])
    end

    it "lets a later matching override win per criterion" do
      expect(thresholds_for("lib/a.rb", "lib/" => {line: 90}, /a\.rb\z/ => {line: 95})).to eq([95])
    end

    it "keeps the defaults an override does not mention" do
      result = instance_double(SimpleCov::Result, files: [two_criterion_file])
      violations = described_class.minimum_by_file(result, {line: 0, branch: 90}, {"lib/" => {line: 90}})

      expect(violations.map { |v| [v[:criterion], v[:expected]] })
        .to contain_exactly([:line, 90], [:branch, 90])
    end

    it "matches a Regexp subclass the way it matches a Regexp" do
      pattern = Class.new(Regexp).new("a\\.rb\\z")
      expect(thresholds_for("lib/a.rb", pattern => {line: 90})).to eq([90])
    end

    it "leaves the defaults alone when nothing matches" do
      expect(thresholds_for("lib/a.rb", "app/" => {line: 95})).to eq([])
    end
  end

  describe ".minimum_by_group with a missing group" do
    let(:result) { instance_double(SimpleCov::Result, groups: {"Models" => nil}) }

    it "names the missing group and the available ones on stderr" do
      allow(result).to receive(:groups).and_return({"Models" => nil, "Views" => nil}.compact)
      output = capture_stderr { described_class.minimum_by_group(result, "Nope" => {line: 100}) }
      expect(output).to include("no group named 'Nope' exists")
    end

    it "stays silent about it when print_errors is off" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      expect(capture_stderr { described_class.minimum_by_group(result, "Nope" => {line: 100}) }).to be_empty
    end

    it "reports no violations for a group that does not exist" do
      allow(SimpleCov).to receive(:print_errors).and_return(false)
      expect(described_class.minimum_by_group(result, "Nope" => {line: 100})).to eq([])
    end

    it "says nothing about a group that does exist" do
      group = instance_double(SimpleCov::FileList, coverage_statistics: {line: line_stats})
      present = instance_double(SimpleCov::Result, groups: {"Models" => group})
      expect(capture_stderr { described_class.minimum_by_group(present, "Models" => {line: 100}) }).to be_empty
    end
  end
end
