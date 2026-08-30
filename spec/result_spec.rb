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

      # The Coverage.result the process hands over is shared with the
      # merge, so a Result must not be able to edit it underfoot.
      it "freezes the coverage hash it was handed" do
        expect(result.original_result).to be_frozen
      end

      it "stamps itself with the current time when no created_at is given" do
        expect(result.created_at).to be_within(60).of(Time.now)
      end

      it "falls back to the configured command name" do
        allow(SimpleCov).to receive(:command_name).and_return("Fixture Suite")

        expect(described_class.new(original_result).command_name).to eq("Fixture Suite")
      end

      # The merge hands over a Set of every path its workers tracked; the
      # resultset entry is a list.
      it "reads tracked files from any collection, not only an Array" do
        tracked = described_class.new(original_result, tracked_files: Set["/x/one.rb"])

        expect(tracked.tracked_files).to eq(["/x/one.rb"])
      end

      it "has 3 filenames" do
        expect(result.filenames.count).to eq(3)
      end

      # A Set is what keeps the restriction one membership test per
      # recorded file, so the type is part of the promise.
      it "carries its own filenames as a Set for the context restriction" do
        expect(result.send(:context_filenames)).to be_a(Set)
        expect(result.send(:context_filenames)).to eq(Set.new(result.filenames))
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

        # Recorded so a merge in another process can inject the files nobody
        # loaded without needing this process's `cover` / `track_files` config.
        # Omitted when empty so a run that tracks nothing writes the shape it
        # always has. See #1250.
        it "omits tracked_files when nothing was tracked" do
          expect(result.to_hash.values.first).not_to have_key("tracked_files")
        end

        # Only the keys a run actually carries are written, so an entry
        # never claims an identity or a file list it does not have.
        it "writes nothing but coverage and timestamp for a plain run" do
          plain = described_class.new(original_result, command_name: "t")

          expect(plain.to_hash.fetch("t").keys).to eq(%w[coverage timestamp])
        end

        it "writes every optional key the run does carry" do
          full = described_class.new(
            original_result, command_name: "t", run_id: "run-1", worker_id: "worker-2",
                             tracked_files: ["/x/one.rb"], contexts: SimpleCov::ContextMap.new
          )

          expect(full.to_hash.fetch("t").keys).to eq(%w[coverage timestamp run_id worker_id tracked_files contexts])
        end

        it "writes the timestamp as a float, which is what Time.at reads back" do
          stamped = described_class.new(original_result, command_name: "t", created_at: Time.at(100.75))

          expect(stamped.to_hash.fetch("t").fetch("timestamp")).to eq(100.75)
        end

        it "round-trips tracked_files when they were recorded" do
          tracked = ["/some/path/one.rb", "/some/path/two.rb"]
          tracked_result = described_class.new(original_result, command_name: "t", tracked_files: tracked)

          expect(tracked_result.to_hash["t"]["tracked_files"]).to eq(tracked)
          expect(described_class.from_hash(tracked_result.to_hash).first.tracked_files).to eq(tracked)
        end

        it "round-trips parallel run and worker identities" do
          identified = described_class.new(
            original_result, command_name: "t", run_id: "run-1", worker_id: "worker-2"
          )
          restored = described_class.from_hash(identified.to_hash).first

          expect(restored.run_id).to eq("run-1")
          expect(restored.worker_id).to eq("worker-2")
        end

        # A live result's criterion keys are Symbols (ResultAdapter keeps
        # Ruby's Coverage keys), while stored entries parsed back from JSON
        # carry Strings and the combiners read only Strings. Symbol keys in
        # the dump meant a live result merged against a stored entry with
        # the same command name (the #581 concurrent-runner path)
        # contributed nothing for every shared file.
        it "serializes symbol criterion keys as strings" do
          live = described_class.new(
            {source_fixture("sample.rb") => {lines: [nil, 1, 1, 1, nil, nil, 1, 1, nil, nil]}},
            command_name: "t"
          )

          expect(live.to_hash["t"]["coverage"][source_fixture("sample.rb")].keys).to eq ["lines"]
        end

        it "round-trips subsecond timestamps" do
          timestamped = described_class.new(original_result, command_name: "t", created_at: Time.at(100.75))

          expect(described_class.from_hash(timestamped.to_hash).first.created_at.to_f).to eq(100.75)
        end

        it "omits contexts when no per-test map was recorded" do
          expect(result.to_hash.values.first).not_to have_key("contexts")
          expect(described_class.from_hash(result.to_hash).first.contexts).to be_nil
        end

        it "round-trips the per-test map, restricted to this result's own files" do
          map = SimpleCov::ContextMap.new
          map.record("spec/sample_spec.rb:3", source_fixture("sample.rb") => 0b10)
          map.record("spec/other_spec.rb:9", "/somewhere/else/entirely.rb" => 0b1)
          mapped = described_class.new(original_result, command_name: "t", contexts: map)

          dumped = mapped.to_hash["t"]["contexts"]
          expect(dumped["files"].keys).to eq([source_fixture("sample.rb")])

          restored = described_class.from_hash(mapped.to_hash).first.contexts
          expect(restored.covering(source_fixture("sample.rb"), 2)).to eq(["spec/sample_spec.rb:3"])
          expect(restored.contexts).to eq(["spec/sample_spec.rb:3", "spec/other_spec.rb:9"])
        end

        # Presence of the key (even for an empty map) is what lets a merge
        # tell "tracked and covered nothing" from "never tracked".
        it "serializes an empty map rather than omitting it" do
          mapped = described_class.new(original_result, command_name: "t", contexts: SimpleCov::ContextMap.new)

          expect(mapped.to_hash["t"]["contexts"]).to eq("version" => 1, "contexts" => [], "files" => {})
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
        SimpleCov.skip "sample.rb"
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
        result = described_class.new(original_result, filter_config: SimpleCov::Result::FilterConfig.new(filters: []))
        expect(result.source_files.length).to eq(3)
      end

      it "uses the explicitly-passed filters instead of the singleton's" do
        explicit_filter = SimpleCov::StringFilter.new("user.rb")
        filter_config = SimpleCov::Result::FilterConfig.new(filters: [explicit_filter])
        result = described_class.new(original_result, filter_config: filter_config)
        # Drops user.rb, keeps sample.rb (which the global chain would have filtered)
        expect(result.filenames.map { |f| File.basename(f) }).to contain_exactly(
          "sample.rb",
          "sample_controller.rb"
        )
      end

      # The dump carries the files the report carries: a filtered-out file
      # has no place in the entry another process merges against.
      it "serializes coverage only for the files that survived the filters" do
        filtered = described_class.new(original_result, command_name: "t")

        expect(filtered.to_hash.fetch("t").fetch("coverage").keys).to eq(
          [source_fixture("app/controllers/sample_controller.rb"), source_fixture("app/models/user.rb")]
        )
      end

      it "restricts the file set to those matching a cover filter (when any are passed)" do
        only_sample = SimpleCov::GlobFilter.new("spec/fixtures/sample.rb")
        filter_config = SimpleCov::Result::FilterConfig.new(filters: [], cover_filters: [only_sample])
        result = described_class.new(original_result, filter_config: filter_config)
        expect(result.filenames.map { |f| File.basename(f) }).to contain_exactly("sample.rb")
        expect(result.files).to be_a(SimpleCov::FileList)
      end

      # Several `cover` matchers union rather than intersect: a file is
      # kept when any one of them claims it.
      it "keeps a file matched by only one of several cover filters" do
        filter_config = SimpleCov::Result::FilterConfig.new(
          filters: [],
          cover_filters: [SimpleCov::StringFilter.new("user.rb"), SimpleCov::StringFilter.new("sample_controller.rb")]
        )
        result = described_class.new(original_result, filter_config: filter_config)

        expect(result.filenames.map { |f| File.basename(f) }).to contain_exactly(
          "user.rb", "sample_controller.rb"
        )
      end
    end

    context "with groups set up for all files" do
      subject(:result) do
        described_class.new(original_result)
      end

      before do
        SimpleCov.group "Models", "app/models"
        SimpleCov.group "Controllers", ["app/controllers"]
        SimpleCov.group "Other" do |src_file|
          File.basename(src_file.filename) == "sample.rb"
        end
      end

      it "has 3 groups" do
        expect(result.groups.length).to eq(3)
      end

      # The groups come from the configuration the Result was built with,
      # which is not always the singleton's.
      it "groups by an explicitly-passed configuration instead of the singleton's" do
        filter_config = SimpleCov::Result::FilterConfig.new(groups: {"Only Models" => SimpleCov::StringFilter.new("app/models")})
        grouped = described_class.new(original_result, filter_config: filter_config)

        expect(grouped.groups.keys).to eq(["Only Models", "Ungrouped"])
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

        # The stamp is the on-disk signal behind the clobber-prevention
        # backstop; unlike .last_run.json it must appear no matter how
        # the run ends.
        it "touches the report stamp when formatting" do
          Dir.mktmpdir("simplecov-stamp-spec-") do |dir|
            allow(SimpleCov).to receive(:coverage_path).and_return(dir)

            result.format!

            expect(File).to exist(File.join(dir, ".report_stamp"))
          end
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

      # Formatter instances (rather than classes) are how constructor
      # options like `silent: true` reach the built-in formatters; see
      # #1240.
      context "when a formatter instance is configured" do
        before do
          SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter.new
        end

        it "formats with the instance instead of trying to instantiate it" do
          expect(result.format!).to be_a String
        end
      end

      context "when formatters mixes classes and instances" do
        before do
          SimpleCov.formatters = [
            SimpleCov::Formatter::SimpleFormatter,
            SimpleCov::Formatter::SimpleFormatter.new
          ]
        end

        it "formats with each of them" do
          formatted = result.format!
          expect(formatted.count).to eq(2)
          expect(formatted).to all(be_a(String))
        end
      end

      # `formatter false` / `formatters []` opts out of formatting; see #964.
      context "when no formatter is configured (opted out)" do
        before { SimpleCov.formatter(false) }

        it "returns nil from result.format! without raising" do
          expect(result.format!).to be_nil
        end
      end
    end

    context "with groups set up that do not match all files" do
      subject(:result) { described_class.new(original_result) }

      before do
        SimpleCov.configure do
          group "Models", "app/models"
          group "Controllers", "app/controllers"
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

    describe "#command_names" do
      subject(:result) { described_class.new(original_result, command_name: "RSpec") }

      it "defaults to just the command name for a single-run result" do
        expect(result.command_names).to eq(["RSpec"])
      end

      it "carries the distinct run names a merge sets" do
        result.command_names = %w[result1 result2]
        expect(result.command_names).to eq(%w[result1 result2])
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

      it "restores the timestamp as a Time, and every identity the entry carries" do
        input = {
          "rspec" => {
            "coverage" => original_result,
            "timestamp" => 100.75,
            "run_id" => "run-1",
            "worker_id" => "worker-2",
            "tracked_files" => ["/x/one.rb"],
            "contexts" => {"version" => 1, "contexts" => ["spec/sample_spec.rb:3"], "files" => {}}
          }
        }

        restored = described_class.from_hash(input).first

        expect(restored).to have_attributes(
          command_name: "rspec",
          created_at: Time.at(100.75),
          run_id: "run-1",
          worker_id: "worker-2",
          tracked_files: ["/x/one.rb"]
        )
        expect(restored.contexts.contexts).to eq(["spec/sample_spec.rb:3"])
      end

      it "leaves an entry without identities or a context map empty-handed" do
        input = {"rspec" => {"coverage" => original_result, "timestamp" => 100.75}}

        restored = described_class.from_hash(input).first

        expect(restored).to have_attributes(run_id: nil, worker_id: nil, contexts: nil, tracked_files: [])
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

      # Resolution is against SimpleCov.root, not the working directory,
      # so a relative path means the same thing wherever it is looked up.
      it "resolves a relative path against SimpleCov.root, not the process's cwd" do
        relative = Pathname.new(user_path).relative_path_from(Pathname.new(SimpleCov.root)).to_s
        looked_up = result

        Dir.mktmpdir do |elsewhere|
          Dir.chdir(elsewhere) do
            expect(looked_up.source_file_for(relative).filename).to eq(user_path)
          end
        end
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
        stderr = capture_stderr { described_class.new(missing_only, report: true) }
        expect(stderr).to include("dropped all 2 source file(s)")
        expect(stderr).to include("/does/not/exist/foo.rb")
        expect(stderr).to include("/also/missing/bar.rb")
        expect(stderr).to include("SimpleCov.collate")
      end

      it "emits a quieter warning when some-but-not-all source files are missing" do
        partial = original_result.merge("/does/not/exist/foo.rb" => {"lines" => [1, nil]})
        stderr = capture_stderr { described_class.new(partial, report: true) }
        expect(stderr).to include("dropped 1 source file(s)")
        expect(stderr).to include("/does/not/exist/foo.rb")
        expect(stderr).not_to include("SimpleCov.collate")
      end

      it "doesn't warn when every source file is present" do
        stderr = capture_stderr { described_class.new(original_result, report: true) }
        expect(stderr).to be_empty
      end

      # Per-process slices (process_coverage_result) build with report: false
      # so the warning isn't emitted once per parallel worker; only the merged
      # result reports. See issue #1171.
      it "stays silent for a non-reporting result (report: false)" do
        stderr = capture_stderr { described_class.new(missing_only) }
        expect(stderr).to be_empty
      end

      # In a parallel run only the final-result process reports, so the warning
      # is emitted once rather than once per worker. See issue #1171.
      #
      # Real state rather than a partial double: JRuby intermittently kept
      # dispatching to the original final_result_process? through an
      # already-compiled call site, letting the warning through and failing
      # the suite. A forked subprocess is never the final-result process,
      # so marking the real flag exercises the same gate without stubbing.
      it "stays silent when this isn't the final-result process" do
        previous = SimpleCov.current_run
        SimpleCov.current_run = SimpleCov::CurrentRun.new
        SimpleCov.mark_forked_subprocess!
        stderr = capture_stderr { described_class.new(missing_only, report: true) }
        expect(stderr).to be_empty
      ensure
        SimpleCov.current_run = previous
      end

      it "caps the listed paths at five with a `+N more` suffix" do
        many_missing = (1..8).to_h { |n| ["/missing/file#{n}.rb", {"lines" => [1]}] }
        stderr = capture_stderr { described_class.new(many_missing, report: true) }
        expect(stderr).to include("(+3 more)")
      end
    end
  end

  # Reached only through Result#initialize in production, so the shapes it
  # has to survive (symbol criterion keys, a path whose source is gone) are
  # pinned here rather than through a whole formatted report.
  describe SimpleCov::Result::SourceFileBuilder do
    let(:sample) { source_fixture("json/sample.rb") }
    let(:user) { source_fixture("app/models/user.rb") }
    let(:missing) { "/does/not/exist/foo.rb" }

    def builder_for(coverage, not_loaded_files: Set.new)
      described_class.new(coverage, not_loaded_files: not_loaded_files)
    end

    it "builds one source file per path, sorted by filename" do
      builder = builder_for({user => {"lines" => [1]}, sample => {"lines" => [1, 0, 1]}})
      files = builder.call

      expect(files).to be_a(SimpleCov::FileList)
      expect(files.map(&:filename)).to eq([user, sample])
      expect(builder.missing_source_files).to be_empty
    end

    # The report drops what it cannot read, and hands the caller the list so
    # the drop can be said out loud. See #980.
    it "collects the paths whose source is gone instead of building them" do
      builder = builder_for({missing => {"lines" => [1]}, sample => {"lines" => [1, 0, 1]}})

      expect(builder.call.map(&:filename)).to eq([sample])
      expect(builder.missing_source_files).to eq([missing])
    end

    # `Coverage.result` keys the criteria with Symbols; a resultset read
    # back from disk uses Strings, and SourceFile reads Strings.
    it "stringifies the criterion keys a live Coverage.result carries" do
      file = builder_for({sample => {lines: [1, 0, 1]}}).call.first

      expect(file.coverage_statistics(:line)).to have_attributes(covered: 2, missed: 1)
    end

    it "marks a file nobody loaded as not loaded, and every other file as loaded" do
      files = builder_for({user => {"lines" => [1]}, sample => {"lines" => [1, 0, 1]}},
                          not_loaded_files: Set[sample]).call

      expect(files.map(&:not_loaded?)).to eq([false, true])
    end
  end

  # The warning behind issue #980: a resultset naming source files that
  # don't exist here produces an empty "0 / 0 (100.00%)" report that looks
  # like success. These are the exact lines it prints.
  describe SimpleCov::Result::MissingSourceFilesReporter do
    subject(:reporter) { described_class.new(paths, every_entry_dropped: false) }

    let(:paths) { ["/gone/one.rb"] }

    before { allow(SimpleCov::Color).to receive(:enabled?).and_return(true) }

    def message_for(paths, every_entry_dropped:)
      described_class.new(paths, every_entry_dropped: every_entry_dropped).message
    end

    it "points at collate's usual cause when the result kept nothing at all" do
      expect(message_for(["/gone/one.rb", "/gone/two.rb"], every_entry_dropped: true)).to eq(
        "SimpleCov dropped all 2 source file(s) from the result — none of the paths in the " \
        "resultset exist on this filesystem: /gone/one.rb, /gone/two.rb. If you're running " \
        "`SimpleCov.collate`, the source files must be available at the same absolute paths as " \
        "when the individual resultsets were generated."
      )
    end

    it "stays quieter when only some of the files went missing" do
      expect(message_for(["/gone/one.rb"], every_entry_dropped: false)).to eq(
        "SimpleCov dropped 1 source file(s) from the result because they don't exist on this " \
        "filesystem: /gone/one.rb. They were tracked in the resultset but have since moved or " \
        "been removed."
      )
    end

    it "lists five paths without a suffix" do
      five = (1..5).map { |index| "/gone/file#{index}.rb" }

      expect(message_for(five, every_entry_dropped: false)).to include(
        "filesystem: /gone/file1.rb, /gone/file2.rb, /gone/file3.rb, /gone/file4.rb, /gone/file5.rb. They were"
      )
    end

    it "lists the first five paths and counts the rest" do
      six = (1..6).map { |index| "/gone/file#{index}.rb" }

      expect(message_for(six, every_entry_dropped: false)).to include(
        "filesystem: /gone/file1.rb, /gone/file2.rb, /gone/file3.rb, /gone/file4.rb, " \
        "/gone/file5.rb (+1 more). They were"
      )
    end

    it "warns in yellow, the color of a report that looks fine but isn't" do
      expect(capture_stderr { reporter.warn! }).to eq("\e[33m#{reporter.message}\e[0m\n")
    end
  end
end
