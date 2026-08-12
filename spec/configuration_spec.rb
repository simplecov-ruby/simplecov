# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::Configuration do
  let(:config_class) do
    Class.new do
      include SimpleCov::Configuration
    end
  end
  let(:config) { config_class.new }

  # The criterion-first `coverage` method is a uniform front-end over the same
  # threshold stores the flat `minimum_coverage` family writes, so these
  # examples assert against those stores.
  describe "#coverage" do
    after { config.clear_coverage_criteria }

    describe "enabling" do
      it "enables the named criterion just by mentioning it" do
        config.coverage :branch
        expect(config.coverage_criterion_enabled?(:branch)).to be true
      end

      it "disables a criterion with enabled: false" do
        config.coverage :line, enabled: false
        expect(config.coverage_criterion_enabled?(:line)).to be false
      end

      it "selects oneshot mode for line" do
        config.coverage :line, oneshot: true
        expect(config.coverage_criterion_enabled?(:oneshot_line)).to be true
      end

      it "switches back to ordinary lines when line is selected again" do
        config.coverage :line, oneshot: true
        config.coverage :line

        expect(config.coverage_criteria).to contain_exactly(:line)
      end

      it "rejects oneshot mode for non-line criteria" do
        expect { config.coverage :branch, oneshot: true }
          .to raise_error(SimpleCov::ConfigurationError, /only valid for/)
      end

      it "disables oneshot line coverage with enabled: false" do
        config.coverage :line, oneshot: true
        config.coverage :line, oneshot: true, enabled: false

        expect(config.coverage_criterion_enabled?(:oneshot_line)).to be false
      end

      it "sets the primary criterion via a keyword" do
        config.coverage :branch, primary: true
        expect(config.primary_coverage).to eq(:branch)
      end

      it "sets the primary criterion via the block verb" do
        config.coverage(:branch) { primary }
        expect(config.primary_coverage).to eq(:branch)
      end

      it "enables eval coverage" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(true)

        config.coverage :eval
        expect(config.coverage_for_eval_enabled?).to be true
      end

      it "disables eval coverage with enabled: false" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(true)

        config.coverage :eval
        config.coverage :eval, enabled: false

        expect(config.coverage_for_eval_enabled?).to be false
      end

      it "leaves eval coverage off and warns when the runtime does not support it" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(false)

        stderr = capture_stderr { config.coverage :eval }

        expect(config.coverage_for_eval_enabled?).to be false
        expect(stderr).to include("Coverage for eval is not available")
      end

      # `coverage :eval` alone is supported, so the old "Unsupported
      # coverage criterion eval" message was misleading. The refusal is
      # about thresholds specifically.
      it "rejects thresholds for :eval with a message about thresholds, not the criterion" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(true)

        expect { config.coverage :eval, minimum: 100 }
          .to raise_error(SimpleCov::ConfigurationError, /:eval only toggles measuring eval'd code/)
      end
    end

    describe "overall thresholds" do
      it "stores per-criterion minimum / maximum / drop from the one-liner form" do
        config.coverage :branch, minimum: 80, maximum: 95, maximum_drop: 5
        expect(config.minimum_coverage).to eq(branch: 80)
        expect(config.maximum_coverage).to eq(branch: 95)
        expect(config.maximum_coverage_drop).to eq(branch: 5)
      end

      it "stores the same thresholds from the block form" do
        config.coverage :line do
          minimum 90
          maximum_drop 5
        end
        expect(config.minimum_coverage).to eq(line: 90)
        expect(config.maximum_coverage_drop).to eq(line: 5)
      end

      it "pins coverage with exact (sets both minimum and maximum)" do
        config.coverage :line, exact: 95
        expect(config.minimum_coverage).to eq(line: 95)
        expect(config.maximum_coverage).to eq(line: 95)
      end

      it "produces the same store as `minimum_coverage line: 90, branch: 80`" do
        config.coverage :branch, minimum: 80
        config.coverage :line, minimum: 90
        expect(config.minimum_coverage).to eq(line: 90, branch: 80)
      end

      it "rejects a percentage above 100 the same way the flat methods do" do
        expect { config.coverage :line, minimum: 101 }.to output(/greater than 100/).to_stderr
      end

      it "rejects an unknown keyword option" do
        expect { config.coverage :line, minimum_per_group: 80 }
          .to raise_error(SimpleCov::ConfigurationError, /Unknown `coverage` option :minimum_per_group/)
      end
    end

    describe "per-file thresholds" do
      it "sets a default applied to every file (block and keyword forms)" do
        config.coverage(:line) { minimum_per_file 80 }
        expect(config.minimum_coverage_by_file).to eq(line: 80)

        other = config_class.new
        other.coverage :line, minimum_per_file: 80
        expect(other.minimum_coverage_by_file).to eq(line: 80)
      end

      it "overrides the default for a String path or Regexp via only:" do
        config.coverage :line do
          minimum_per_file 80
          minimum_per_file 100, only: "app/mailers/request_mailer.rb"
          minimum_per_file 95, only: %r{\Aapp/payments/}
        end
        expect(config.minimum_coverage_by_file).to eq(line: 80)
        expect(config.minimum_coverage_by_file_overrides).to eq(
          "app/mailers/request_mailer.rb" => {line: 100},
          %r{\Aapp/payments/} => {line: 95}
        )
      end

      it "keeps line and branch overrides for the same path independent" do
        config.coverage(:line) { minimum_per_file 100, only: "app/x.rb" }
        config.coverage(:branch) { minimum_per_file 90, only: "app/x.rb" }
        expect(config.minimum_coverage_by_file_overrides).to eq("app/x.rb" => {line: 100, branch: 90})
      end

      it "rejects a non-String/Regexp only: target" do
        expect { config.coverage(:line) { minimum_per_file 100, only: :line } }
          .to raise_error(SimpleCov::ConfigurationError, /must be a String path or Regexp/)
      end

      it "starts with empty defaults and overrides" do
        expect(config.minimum_coverage_by_file).to eq({})
        expect(config.minimum_coverage_by_file_overrides).to eq({})
      end
    end

    describe "per-group thresholds" do
      it "stores a per-criterion minimum under the named group" do
        config.coverage(:line) { minimum_per_group 95, only: "Models" }
        config.coverage(:branch) { minimum_per_group 90, only: "Models" }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95, branch: 90})
      end

      # `group :Models` normalizes to the String "Models", so the threshold
      # store must too. A Symbol key here missed the check-time lookup and
      # silently left the minimum unenforced.
      it "normalizes a Symbol only: target to match Symbol-defined groups" do
        config.coverage(:line) { minimum_per_group 95, only: :Models }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95})
      end

      it "starts empty" do
        expect(config.minimum_coverage_by_group).to eq({})
      end

      it "raises when the criterion is not enabled" do
        expect { config.coverage(:branch, enabled: false) { minimum_per_group 90, only: "Models" } }
          .to raise_error(/branch.*disabled/i)
      end
    end
  end

  describe "#print_errors" do
    context "when not manually set" do
      it "defaults to true" do
        expect(config.print_errors).to be true
      end
    end

    context "when set via #print_errors" do
      before { config.print_errors false }

      it "reads back the assigned value" do
        expect(config.print_errors).to be false
      end
    end
  end

  describe "#source_in_json" do
    it "defaults to true" do
      expect(config.source_in_json).to be true
    end

    it "reads back the assigned value" do
      config.source_in_json false
      expect(config.source_in_json).to be false
    end

    it "round-trips a true assignment" do
      config.source_in_json false
      config.source_in_json true
      expect(config.source_in_json).to be true
    end
  end

  describe "#color" do
    context "when not manually set" do
      it "defaults to :auto" do
        expect(config.color).to eq(:auto)
      end
    end

    context "when set to true" do
      before { config.color true }

      it "reads back the assigned value" do
        expect(config.color).to be true
      end
    end

    context "when set to false" do
      before { config.color false }

      it "reads back the assigned value" do
        expect(config.color).to be false
      end
    end

    context "when set back to :auto" do
      before do
        config.color true
        config.color :auto
      end

      it "reads back :auto" do
        expect(config.color).to eq(:auto)
      end
    end
  end

  describe "#project_name" do
    it "uses the basename of the configured root, capitalized" do
      config.root("/Users/erik/Code/my_app")
      expect(config.project_name).to eq("My app")
    end

    it "does not raise when root is the filesystem root" do
      config.root("/")
      expect { config.project_name }.not_to raise_error
    end
  end

  describe "#coverage_path" do
    let(:tmp) { Dir.mktmpdir }

    before { config.root(tmp) }
    after { FileUtils.remove_entry(tmp) }

    it "defaults to root + coverage_dir" do
      expect(config.coverage_path).to eq(File.join(tmp, "coverage"))
    end

    it "tracks changes to coverage_dir" do
      config.coverage_dir("cov")
      expect(config.coverage_path).to eq(File.join(tmp, "cov"))
    end

    it "accepts an explicit absolute path and overrides the root+dir construction (#716)" do
      Dir.mktmpdir do |out|
        config.coverage_path(out)
        expect(config.coverage_path).to eq(out)
      end
    end

    it "creates the directory when set explicitly" do
      Dir.mktmpdir do |parent|
        target = File.join(parent, "build", "coverage")
        config.coverage_path(target)
        expect(File.directory?(target)).to be(true)
      end
    end

    it "does not let a later coverage_dir change override the explicit path" do
      Dir.mktmpdir do |out|
        config.coverage_path(out)
        config.coverage_dir("ignored")
        expect(config.coverage_path).to eq(out)
      end
    end

    it "does not let a later root change override the explicit path" do
      Dir.mktmpdir do |out|
        config.coverage_path(out)
        Dir.mktmpdir do |other_root|
          config.root(other_root)
          expect(config.coverage_path).to eq(out)
        end
      end
    end

    it "expands a relative explicit path against the current working directory" do
      Dir.mktmpdir do |cwd|
        Dir.chdir(cwd) do
          config.coverage_path("build/cov")
          # `File.realpath` so we compare against the same symlink-resolved
          # form `File.expand_path` returns (on macOS `/var` -> `/private/var`).
          expect(config.coverage_path).to eq(File.join(File.realpath(cwd), "build/cov"))
        end
      end
    end
  end

  describe "#tracked_files" do
    # The bundled `rails` profile writes the ivar directly; nothing in the
    # public API sets it, which is the point of keeping the reader private.
    context "when a profile has set the discovery glob" do
      let(:glob) { "{app,lib}/**/*.rb" }

      before { config.instance_variable_set(:@tracked_files, glob) }

      it "returns the configured glob" do
        expect(config.tracked_files).to eq glob
      end
    end

    context "when unconfigured" do
      it "returns nil" do
        expect(config.tracked_files).to be_nil
      end
    end

    describe "#cover" do
      it "stores a string glob as a GlobFilter" do
        config.cover "lib/**/*.rb"

        expect(config.cover_filters.size).to eq 1
        expect(config.cover_filters.first).to be_a(SimpleCov::GlobFilter)
        expect(config.cover_globs).to eq ["lib/**/*.rb"]
      end

      it "accepts multiple arguments and unions them" do
        config.cover "lib/**/*.rb", "app/**/*.rb"

        expect(config.cover_globs).to eq ["lib/**/*.rb", "app/**/*.rb"]
      end

      it "accepts a Regexp" do
        config.cover(/_service\.rb\z/)

        expect(config.cover_filters.first).to be_a(SimpleCov::RegexFilter)
      end

      it "accepts a block predicate" do
        config.cover { |sf| sf.filename.end_with?("foo.rb") }

        expect(config.cover_filters.first).to be_a(SimpleCov::BlockFilter)
      end

      it "accepts a Proc passed positionally" do
        config.cover(proc { |sf| sf.filename.end_with?("foo.rb") })

        expect(config.cover_filters.first).to be_a(SimpleCov::BlockFilter)
      end

      it "passes a SimpleCov::Filter instance through unchanged" do
        existing = SimpleCov::GlobFilter.new("lib/**/*.rb")
        config.cover(existing)

        expect(config.cover_filters.first).to equal(existing)
      end

      it "wraps an Array of matchers in an ArrayFilter" do
        config.cover(["lib/**/*.rb", /_helper\.rb\z/])

        expect(config.cover_filters.first).to be_a(SimpleCov::ArrayFilter)
      end

      # Without recursion, `cover_globs.grep(GlobFilter)` only saw the top-level
      # filters, so an array-wrapped glob silently failed to drive unloaded-file
      # discovery (Copilot review on #1188).
      it "collects globs nested inside an ArrayFilter for unloaded-file discovery" do
        config.cover(["lib/**/*.rb", /_helper\.rb\z/])

        expect(config.cover_globs).to eq ["lib/**/*.rb"]
      end

      it "ignores non-glob cover filters when collecting globs (Regexp, Block)" do
        config.cover(/_service\.rb\z/) { |sf| sf.filename.end_with?("foo.rb") }

        expect(config.cover_globs).to be_empty
      end

      it "raises on unsupported argument types" do
        expect { config.cover(42) }.to raise_error(SimpleCov::ConfigurationError, /Unsupported `cover` argument/)
      end
    end

    describe "#skip" do
      it "appends one exclusion filter per call, without warning" do
        config.skip "lib/legacy"
        stderr = capture_stderr { config.skip "lib/another" }

        expect(stderr).to be_empty
        expect(config.filters.size).to eq 2
      end
    end

    describe "#group" do
      it "defines a group without warning" do
        stderr = capture_stderr { config.group "Models", "app/models" }

        expect(stderr).to be_empty
        expect(config.groups.keys).to eq ["Models"]
      end

      it "reserves Ungrouped for files that match no configured group" do
        config.group "Models", "app/models"

        expect { config.group "Ungrouped", // }
          .to raise_error(SimpleCov::ConfigurationError, /reserved/)
        expect(config.groups.keys).to eq ["Models"]
      end

      it "rejects the reserved name when replacing the groups hash" do
        config.group "Models", "app/models"
        replacement = {"Ungrouped" => SimpleCov::StringFilter.new("lib")}

        expect { config.groups = replacement }
          .to raise_error(SimpleCov::ConfigurationError, /reserved/)
        expect(config.groups.keys).to eq ["Models"]
      end

      it "normalizes a Symbol group name to its String spelling" do
        config.group :Models, "app/models"

        expect(config.groups.keys).to eq ["Models"]
      end

      it "keeps a Symbol spelling from bypassing the reserved name" do
        expect { config.group :Ungrouped, // }
          .to raise_error(SimpleCov::ConfigurationError, /reserved/)
        expect(config.groups).to be_empty
      end

      it "rejects group names that are neither String nor Symbol" do
        expect { config.group 42, // }
          .to raise_error(SimpleCov::ConfigurationError, /Group names must be Strings/)
        expect(config.groups).to be_empty
      end

      it "normalizes Symbol keys when replacing the groups hash" do
        config.groups = {Models: SimpleCov::StringFilter.new("app/models")}

        expect(config.groups.keys).to eq ["Models"]
      end

      it "rejects a Symbol spelling of the reserved name in a replacement hash" do
        expect { config.groups = {Ungrouped: SimpleCov::StringFilter.new("lib")} }
          .to raise_error(SimpleCov::ConfigurationError, /reserved/)
        expect(config.groups).to be_empty
      end
    end

    describe "#no_default_skips" do
      it "clears every previously installed filter" do
        config.skip "lib/legacy"
        config.no_default_skips

        expect(config.filters).to be_empty
      end
    end

    describe "#merging" do
      around do |example|
        previous = config.instance_variable_get(:@merging)
        config.instance_variable_set(:@merging, nil)
        example.run
        config.instance_variable_set(:@merging, previous)
      end

      it "defaults to true" do
        expect(config.merging).to be true
      end

      it "stores the explicit false" do
        config.merging false
        expect(config.merging).to be false
      end
    end

    describe "#finalize_merge" do
      let(:adapter) do
        Class.new(SimpleCov::ParallelAdapters::Base) do
          def self.expected_worker_count
            3
          end
        end
      end

      around do |example|
        previous_env = ENV.values_at("TEST_ENV_NUMBER", "PARALLEL_TEST_GROUPS")
        previous_ivars = %i[
          @finalize_merge @finalize_merge_explicit @finalize_merge_inference_warned
        ].filter_map do |ivar|
          [ivar, config.instance_variable_get(ivar)] if config.instance_variable_defined?(ivar)
        end

        %w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS].each { |key| ENV.delete(key) }
        %i[@finalize_merge @finalize_merge_explicit @finalize_merge_inference_warned].each do |ivar|
          config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
        end

        example.run
      ensure
        ENV["TEST_ENV_NUMBER"], ENV["PARALLEL_TEST_GROUPS"] = previous_env
        %i[@finalize_merge @finalize_merge_explicit @finalize_merge_inference_warned].each do |ivar|
          config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
        end
        previous_ivars.each { |ivar, value| config.instance_variable_set(ivar, value) }
      end

      it "defaults to true" do
        expect(config.finalize_merge).to be true
      end

      it "stores an explicit false" do
        config.finalize_merge false
        expect(config.finalize_merge).to be false
      end

      it "stores an explicit true" do
        config.finalize_merge true
        expect(config.finalize_merge).to be true
      end

      it "selects only the final process as the merge finalization owner" do
        config.finalize_merge true
        allow(config).to receive_messages(collating_result?: false, final_result_process?: false)

        expect(config.merge_finalization_owner?).to be false

        allow(config).to receive(:final_result_process?).and_return(true)
        expect(config.merge_finalization_owner?).to be true
      end

      it "always gives merge finalization ownership to collation" do
        config.finalize_merge false
        allow(config).to receive_messages(collating_result?: true, final_result_process?: false)

        expect(config.merge_finalization_owner?).to be true
      end

      it "does not warn when the explicit value is false" do
        stderr = capture_stderr { config.finalize_merge false }
        expect(stderr).to be_empty
      end

      it "infers false and warns for externally finalized parallel resultsets" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        stderr = capture_stderr do
          expect(config.finalize_merge).to be false
        end

        expect(stderr).to include("SimpleCov inferred `finalize_merge false`")
        expect(stderr).to include("`SimpleCov.finalize_merge false`")
        expect(stderr).to include("`SimpleCov.finalize_merge true`")
        expect(stderr).to include("#merge-finalization-ownership")
      end

      it "keeps the inferred warning to one emission" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        stderr = capture_stderr do
          2.times { config.finalize_merge }
        end

        expect(stderr.scan("SimpleCov inferred").size).to eq(1)
      end

      it "stays silent when print_errors is false" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        config.print_errors false
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        stderr = capture_stderr do
          expect(config.finalize_merge).to be false
        end

        expect(stderr).to be_empty
      end

      it "does not infer false without an active parallel adapter" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(nil)

        expect(config.finalize_merge).to be true
      end

      it "does not infer false for a single-worker parallel run" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "1"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current)
          .and_return(Class.new(SimpleCov::ParallelAdapters::Base))

        expect(config.finalize_merge).to be true
      end

      it "does not infer false when merging is disabled" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging false
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        expect(config.finalize_merge).to be true
      end

      it "does not infer false without an explicitly custom coverage destination" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        expect(config.finalize_merge).to be true
      end

      it "does not infer false outside a parallel worker environment" do
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        expect(config.finalize_merge).to be true
      end
    end

    describe "#merge_subprocesses" do
      it "returns false by default" do
        expect(config.merge_subprocesses).to be false
      end

      it "stores the explicit value" do
        config.merge_subprocesses true
        expect(config.merge_subprocesses).to be true
      end
    end

    describe "#parallel_tests" do
      around do |example|
        had_ivar = config.instance_variable_defined?(:@parallel_tests)
        prev = config.instance_variable_get(:@parallel_tests) if had_ivar
        config.remove_instance_variable(:@parallel_tests) if had_ivar
        example.run
      ensure
        config.remove_instance_variable(:@parallel_tests) if config.instance_variable_defined?(:@parallel_tests)
        config.instance_variable_set(:@parallel_tests, prev) if had_ivar
      end

      it "returns nil (auto-detect) by default" do
        expect(config.parallel_tests).to be_nil
      end

      it "stores an explicit opt-in" do
        config.parallel_tests true
        expect(config.parallel_tests).to be true
      end

      it "stores an explicit opt-out" do
        config.parallel_tests false
        expect(config.parallel_tests).to be false
      end
    end

    describe "#enable_coverage with :eval" do
      context "when the runtime supports eval coverage" do
        before { allow(config).to receive(:coverage_for_eval_supported?).and_return(true) }

        it "flips coverage_for_eval_enabled? to true" do
          config.enable_coverage :eval

          expect(config.coverage_for_eval_enabled?).to be true
        end

        it "combines with regular criteria in one call" do
          config.enable_coverage :branch, :eval

          expect(config.coverage_criteria).to include :branch
          expect(config.coverage_for_eval_enabled?).to be true
        end
      end
    end

    shared_examples "setting coverage expectations" do |coverage_setting|
      after do
        config.clear_coverage_criteria
      end

      it "does not warn that coverage exceeds 100% for a valid value" do
        allow(config).to receive(:warn)
        config.public_send(coverage_setting, 100.00)
        expect(config).not_to have_received(:warn).with(/is greater than 100%/)
      end

      it "warns you about your usage" do
        allow(config).to receive(:warn)
        config.public_send(coverage_setting, 100.01)
        expect(config).to have_received(:warn).with("The coverage you set for #{coverage_setting} is greater than 100%")
      end

      it "sets the right coverage value when called with a number" do
        config.public_send(coverage_setting, 80)

        expect(config.public_send(coverage_setting)).to eq line: 80
      end

      it "sets the right coverage when called with a hash of just line" do
        config.public_send(coverage_setting, {line: 85.0})

        expect(config.public_send(coverage_setting)).to eq line: 85.0
      end

      it "sets the right coverage when called with a hash of just branch" do
        config.enable_coverage :branch
        config.public_send(coverage_setting, {branch: 85.0})

        expect(config.public_send(coverage_setting)).to eq branch: 85.0
      end

      it "sets the right coverage when called with both line and branch" do
        config.enable_coverage :branch
        config.public_send(coverage_setting, {branch: 85.0, line: 95.4})

        expect(config.public_send(coverage_setting)).to eq branch: 85.0, line: 95.4
      end

      it "raises when trying to set branch coverage but not enabled" do
        expect do
          config.public_send(coverage_setting, {branch: 42})
        end.to raise_error(/branch.*disabled/i)
      end

      it "raises when unknown coverage criteria provided" do
        expect do
          config.public_send(coverage_setting, {unknown: 42})
        end.to raise_error(/unsupported.*unknown/i)
      end

      context "when primary coverage is set" do
        before do
          config.enable_coverage :branch
          config.primary_coverage :branch
        end

        it "sets the right coverage value when called with a number" do
          config.public_send(coverage_setting, 80)

          expect(config.public_send(coverage_setting)).to eq branch: 80
        end
      end
    end

    describe "#minimum_coverage" do
      it_behaves_like "setting coverage expectations", :minimum_coverage
    end

    describe "#maximum_coverage" do
      it_behaves_like "setting coverage expectations", :maximum_coverage
    end

    describe "#expected_coverage" do
      after { config.clear_coverage_criteria }

      it "sets both minimum_coverage and maximum_coverage when called with a number" do
        config.expected_coverage(95.42)

        expect(config.minimum_coverage).to eq line: 95.42
        expect(config.maximum_coverage).to eq line: 95.42
      end

      it "sets both when called with a per-criterion hash" do
        config.enable_coverage :branch
        config.expected_coverage(line: 90.0, branch: 85.0)

        expect(config.minimum_coverage).to eq line: 90.0, branch: 85.0
        expect(config.maximum_coverage).to eq line: 90.0, branch: 85.0
      end

      it "returns the current minimum_coverage when called with no argument" do
        config.expected_coverage(95.42)

        expect(config.expected_coverage).to eq line: 95.42
      end

      it "returns the empty default when nothing has been configured" do
        expect(config.expected_coverage).to eq({})
      end

      it "raises when an unknown criterion is provided" do
        expect { config.expected_coverage(unknown: 42) }.to raise_error(/unsupported.*unknown/i)
      end
    end

    describe "#maximum_coverage_drop" do
      it_behaves_like "setting coverage expectations", :maximum_coverage_drop
    end

    describe "#refuse_coverage_drop" do
      after do
        config.clear_coverage_criteria
      end

      it "sets the right coverage value when called with `:line`" do
        config.refuse_coverage_drop(:line)

        expect(config.maximum_coverage_drop).to eq line: 0
      end

      it "sets the right coverage value when called with `:branch`" do
        config.enable_coverage :branch
        config.refuse_coverage_drop(:branch)

        expect(config.maximum_coverage_drop).to eq branch: 0
      end

      it "sets the right coverage value when called with `:line` and `:branch`" do
        config.enable_coverage :branch
        config.refuse_coverage_drop(:line, :branch)

        expect(config.maximum_coverage_drop).to eq line: 0, branch: 0
      end

      it "sets the right coverage value when called with no args" do
        config.refuse_coverage_drop

        expect(config.maximum_coverage_drop).to eq line: 0
      end
    end

    describe "#coverage_criteria" do
      it "defaults to line" do
        expect(config.coverage_criteria).to contain_exactly :line
      end
    end

    describe "#enable_coverage" do
      it "can enable branch coverage" do
        config.enable_coverage :branch

        expect(config.coverage_criteria).to contain_exactly :line, :branch
      end

      it "can enable line again" do
        config.enable_coverage :line

        expect(config.coverage_criteria).to contain_exactly :line
      end

      it "replaces line with oneshot line coverage and resets its primary" do
        config.primary_coverage :line
        config.enable_coverage :oneshot_line

        expect(config.coverage_criteria).to contain_exactly(:oneshot_line)
        expect(config.primary_coverage).to eq(:oneshot_line)
      end

      it "replaces oneshot line coverage with line and resets its primary" do
        config.enable_coverage :oneshot_line
        config.primary_coverage :oneshot_line
        config.enable_coverage :line

        expect(config.coverage_criteria).to contain_exactly(:line)
        expect(config.primary_coverage).to eq(:line)
      end

      it "lets the last variadic line mode win without removing other criteria" do
        config.enable_coverage :branch, :method, :oneshot_line, :line
        expect(config.coverage_criteria).to contain_exactly(:branch, :method, :line)

        config.enable_coverage :line, :oneshot_line
        expect(config.coverage_criteria).to contain_exactly(:branch, :method, :oneshot_line)
      end

      it "can't enable arbitrary things" do
        expect do
          config.enable_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end

    describe "#ignore_branches" do
      it "defaults to empty" do
        expect(config.ignored_branches).to eq []
      end

      it "stores a single token" do
        config.ignore_branches :implicit_else

        expect(config.ignored_branches).to eq [:implicit_else]
        expect(config.ignored_branch?(:implicit_else)).to be true
      end

      it "is variadic and unions across calls" do
        config.ignore_branches :implicit_else
        config.ignore_branches :implicit_else # duplicate is a no-op

        expect(config.ignored_branches).to eq [:implicit_else]
      end

      it "raises on an unknown token" do
        expect { config.ignore_branches :implict_else }
          .to raise_error(SimpleCov::ConfigurationError, /Unsupported branch type :implict_else/)
      end

      it "names the supported tokens in the error message" do
        expect { config.ignore_branches :nope }
          .to raise_error(SimpleCov::ConfigurationError, /Supported values are \[:implicit_else, :eval_generated\]/)
      end

      it "stores the setting even when branch coverage is not enabled" do
        # Branch coverage is off by default; only :line is in coverage_criteria.
        expect(config.coverage_criteria).to contain_exactly :line
        config.ignore_branches :implicit_else

        # No raise, setting persists for later.
        expect(config.ignored_branch?(:implicit_else)).to be true
      end

      it "is order-independent with respect to enable_coverage" do
        config.ignore_branches :implicit_else
        config.enable_coverage :branch

        expect(config.coverage_criteria).to include :branch
        expect(config.ignored_branch?(:implicit_else)).to be true
      end

      it "accepts :eval_generated alongside :implicit_else" do
        config.ignore_branches :implicit_else, :eval_generated

        expect(config.ignored_branch?(:implicit_else)).to be true
        expect(config.ignored_branch?(:eval_generated)).to be true
      end
    end

    describe "#ignore_methods" do
      it "starts empty" do
        expect(config.ignored_methods).to eq []
      end

      it "records the requested token" do
        config.ignore_methods :eval_generated

        expect(config.ignored_methods).to eq [:eval_generated]
        expect(config.ignored_method?(:eval_generated)).to be true
      end

      it "deduplicates across calls" do
        config.ignore_methods :eval_generated
        config.ignore_methods :eval_generated

        expect(config.ignored_methods).to eq [:eval_generated]
      end

      it "raises on an unknown token" do
        expect { config.ignore_methods :nope }
          .to raise_error(SimpleCov::ConfigurationError,
                          /Unsupported method type :nope.*Supported values are \[:eval_generated\]/m)
      end

      it "stores the setting even when method coverage is not enabled" do
        expect(config.coverage_criteria).to contain_exactly :line
        config.ignore_methods :eval_generated

        expect(config.ignored_method?(:eval_generated)).to be true
      end
    end

    describe "#disable_coverage" do
      it "removes the criterion from the enabled set" do
        config.enable_coverage :branch
        config.disable_coverage :line

        expect(config.coverage_criteria).to contain_exactly :branch
      end

      it "leaves the set empty when the only enabled criterion is disabled" do
        config.disable_coverage :line

        expect(config.coverage_criteria).to be_empty
      end

      it "rejects unsupported criteria" do
        expect { config.disable_coverage :unknown }.to raise_error(/unsupported.*unknown/i)
      end

      it "clears @primary_coverage so the next read picks a still-enabled criterion" do
        config.enable_coverage :branch
        config.primary_coverage :line
        config.disable_coverage :line

        expect(config.primary_coverage).to eq :branch
      end

      it "turns the eval toggle back off" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(true)
        config.enable_coverage :eval

        config.disable_coverage :eval

        expect(config.coverage_for_eval_enabled?).to be false
      end
    end

    describe "#validate_coverage_criteria!" do
      it "raises when every criterion has been disabled" do
        config.disable_coverage :line
        expect { config.validate_coverage_criteria! }
          .to raise_error(SimpleCov::ConfigurationError, /At least one coverage criterion/)
      end

      it "passes when at least one criterion is enabled" do
        config.enable_coverage :branch
        config.disable_coverage :line
        expect { config.validate_coverage_criteria! }.not_to raise_error
      end
    end

    describe "#primary_coverage default" do
      it "falls back to the first enabled criterion when :line is disabled" do
        config.enable_coverage :branch
        config.disable_coverage :line

        expect(config.primary_coverage).to eq :branch
      end
    end

    describe "#line_coverage?" do
      it "returns true when line coverage is being measured" do
        expect(config).to be_line_coverage
      end

      it "returns true for oneshot lines, which still yield line data" do
        config.enable_coverage :oneshot_line

        expect(config).to be_line_coverage
      end

      it "returns false when line coverage has been disabled" do
        config.enable_coverage :branch
        config.disable_coverage :line

        expect(config).not_to be_line_coverage
      end
    end

    describe "#branch_coverage?", if: SimpleCov.branch_coverage_supported? do
      it "returns true of branch coverage is being measured" do
        config.enable_coverage :branch

        expect(config).to be_branch_coverage
      end

      it "returns false for line coverage" do
        config.primary_coverage :line

        expect(config).not_to be_branch_coverage
      end
    end

    describe "#method_coverage?", if: SimpleCov.method_coverage_supported? do
      it "returns true if method coverage is being measured" do
        config.enable_coverage :method

        expect(config).to be_method_coverage
      end

      it "returns false for line coverage" do
        config.primary_coverage :line

        expect(config).not_to be_method_coverage
      end
    end

    describe "#enable_coverage with :method" do
      it "can enable method coverage" do
        config.enable_coverage :method

        expect(config.coverage_criteria).to contain_exactly :line, :method
      end
    end

    describe "#coverage_for_eval_enabled?" do
      it "is false by default" do
        expect(config.coverage_for_eval_enabled?).to be false
      end
    end

    describe "#formatter" do
      after do
        config.instance_variable_set(:@formatter, SimpleCov::Formatter::HTMLFormatter)
      end

      # `formatter false` / `formatters []` is the documented opt-out path
      # for workers in a parallel CI run that only need their
      # `.resultset.json`; see #964 and the bundled `:collate_worker`
      # profile.
      it "treats false as an explicit opt-out (no raise)" do
        config.formatter(false)
        expect(config.formatter).to be_nil
        expect(config.formatters).to eq([])
      end

      it "treats nil as an explicit opt-out (no raise)" do
        config.formatter(nil)
        expect(config.formatter).to be_nil
      end
    end

    describe "#formatters" do
      after do
        config.instance_variable_set(:@formatter, SimpleCov::Formatter::HTMLFormatter)
      end

      it "wraps a single formatter as an Array" do
        config.formatter = SimpleCov::Formatter::SimpleFormatter
        expect(config.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
      end

      it "accepts an empty Array as an explicit opt-out" do
        config.formatters([])
        expect(config.formatter).to be_nil
        expect(config.formatters).to eq([])
      end

      it "accepts a single formatter that is not wrapped in an Array" do
        config.formatters = SimpleCov::Formatter::SimpleFormatter
        expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
      end

      # `SimpleCov.formatters = MultiFormatter.new([...])` is the pattern
      # the README documented for years (and net-imap still uses).
      # `MultiFormatter.new` returns a Class, not an Array, so the setter
      # must normalize its input like the pre-1.0 implementation did.
      it "accepts a MultiFormatter (a Class) and keeps its format chain working" do
        formatter = Class.new { def format(_) = "ok" }
        config.formatters = SimpleCov::Formatter::MultiFormatter.new([formatter])

        result = instance_double(SimpleCov::Result)
        expect(config.formatter.new.format(result).flatten).to eq(["ok"])
      end

      it "treats nil as an explicit opt-out" do
        config.formatters = nil
        expect(config.formatter).to be_nil
        expect(config.formatters).to eq([])
      end

      it "treats false as an explicit opt-out, like `formatter false`" do
        # `Array(false)` is `[false]`, so without normalization this would
        # configure a MultiFormatter over `false` that fails every report.
        config.formatters = false
        expect(config.formatter).to be_nil
        expect(config.formatters).to eq([])
      end
    end

    describe "#at_exit" do
      around do |example|
        previous = config.instance_variable_get(:@at_exit)
        config.instance_variable_set(:@at_exit, nil)
        example.run
        config.instance_variable_set(:@at_exit, previous)
      end

      it "returns a default proc when called with no block while Coverage is running" do
        allow(Coverage).to receive(:running?).and_return(true)
        proc_returned = config.at_exit
        expect(proc_returned).to be_a(Proc)
      end

      it "formats from the default proc when this process owns the final report" do
        result = instance_double(SimpleCov::Result)
        allow(result).to receive(:format!)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: true)

        config.at_exit.call

        expect(SimpleCov).to have_received(:result)
        expect(result).to have_received(:format!)
      end

      it "still formats from the final process when parallel results are incomplete" do
        result = instance_double(SimpleCov::Result)
        allow(result).to receive(:format!)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov).to receive_messages(
          result: result,
          merge_finalization_owner?: true,
          ready_to_process_results?: false
        )

        config.at_exit.call

        expect(result).to have_received(:format!)
      end

      it "stores the result but does not format from non-final parallel workers" do
        result = instance_double(SimpleCov::Result)
        allow(result).to receive(:format!)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: false)

        config.at_exit.call

        expect(SimpleCov).to have_received(:result)
        expect(result).not_to have_received(:format!)
      end

      it "remembers an explicit block across calls" do
        explicit = proc {}
        config.at_exit(&explicit)
        expect(config.at_exit).to equal(explicit)
      end

      it "returns a no-op when no session is active and no block is stored" do
        allow(SimpleCov).to receive_messages(result?: false, result: nil)
        allow(Coverage).to receive(:running?).and_return(false)
        config.at_exit.call
        expect(SimpleCov).not_to have_received(:result)
      end
    end

    describe "#at_fork" do
      around do |example|
        previous = SimpleCov.instance_variable_get(:@at_fork)
        SimpleCov.instance_variable_set(:@at_fork, nil)
        example.run
        SimpleCov.instance_variable_set(:@at_fork, previous)
      end

      it "remembers an explicit block across calls" do
        explicit = proc { |_pid| }
        SimpleCov.at_fork(&explicit)
        expect(SimpleCov.at_fork).to equal(explicit)
      end

      it "default lambda re-applies subprocess-friendly config" do
        # Stub the global mutations so this spec doesn't trash the rest
        # of the suite's SimpleCov configuration / restart Coverage.
        allow(SimpleCov).to receive(:command_name)
        allow(SimpleCov).to receive(:print_errors)
        allow(SimpleCov).to receive(:formatter)
        allow(SimpleCov).to receive(:minimum_coverage)
        allow(SimpleCov).to receive(:start)
        # Names the subprocess from the stable fork serial, not the pid
        # argument (which varies run to run). See #1171.
        allow(SimpleCov).to receive(:subprocess_serial).and_return(3)

        SimpleCov.at_fork.call(12_345)

        expect(SimpleCov).to have_received(:command_name).with(/subprocess: 3/)
        expect(SimpleCov).to have_received(:print_errors).with(false)
        expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
        expect(SimpleCov).to have_received(:minimum_coverage).with(0)
        expect(SimpleCov).to have_received(:start)
      end
    end

    describe "#subprocess_serial" do
      around do |example|
        previous = SimpleCov.instance_variable_get(:@subprocess_serial)
        example.run
      ensure
        SimpleCov.instance_variable_set(:@subprocess_serial, previous)
      end

      it "defaults to 0 and increments monotonically" do
        SimpleCov.instance_variable_set(:@subprocess_serial, nil)

        expect(SimpleCov.subprocess_serial).to eq(0)
        SimpleCov.next_subprocess_serial!
        SimpleCov.next_subprocess_serial!
        expect(SimpleCov.subprocess_serial).to eq(2)
      end
    end

    describe "#command_name" do
      after { config.instance_variable_set(:@command_name, nil) }

      it "stores an explicit name" do
        config.command_name("My Suite")
        expect(config.command_name).to eq("My Suite")
      end
    end

    describe "#project_name" do
      after { config.instance_variable_set(:@project_name, nil) }

      it "stores an explicit name" do
        config.project_name("Custom")
        expect(config.project_name).to eq("Custom")
      end
    end

    describe "#merge_timeout" do
      after { config.instance_variable_set(:@merge_timeout, nil) }

      it "stores an explicit integer value" do
        config.merge_timeout(120)
        expect(config.merge_timeout).to eq(120)
      end
    end

    describe "#parallel_wait_timeout" do
      after { config.instance_variable_set(:@parallel_wait_timeout, nil) }

      it "defaults to 60 seconds" do
        expect(config.parallel_wait_timeout).to eq(60)
      end

      it "stores an explicit integer value" do
        config.parallel_wait_timeout(180)
        expect(config.parallel_wait_timeout).to eq(180)
      end

      it "ignores a non-integer value" do
        config.parallel_wait_timeout("soon")
        expect(config.parallel_wait_timeout).to eq(60)
      end
    end

    describe "#parse_filter" do
      it "raises when given neither a filter argument nor a block" do
        expect { config.send(:parse_filter) }.to raise_error(ArgumentError, /filter or a block/)
      end
    end

    describe "#configure" do
      it "requires a configuration block" do
        expect { config.configure }.to raise_error(ArgumentError, /configuration block required/)
      end

      it "evaluates a zero-parameter block on the real configuration target" do
        observed = nil

        configured = config.configure do
          @configured = true
          observed = [self, binding.receiver, object_id, singleton_class]
        end

        expect(config.instance_variable_get(:@configured)).to be true
        expect(observed).to eq([config, config, config.object_id, config.singleton_class])
        expect(configured).to be(config)
      end

      it "keeps caller context in a parameterized block and passes the target explicitly" do
        owner_class = Class.new do
          attr_reader :configured_self

          def initialize
            @threshold = 92
          end

          def apply_threshold(target)
            @configured_self = self
            target.minimum_coverage @threshold
          end
        end
        owner = owner_class.new

        configured = owner.instance_exec(config) do |target|
          target.configure { |dsl| apply_threshold(dsl) }
        end

        expect(config.minimum_coverage).to eq(line: 92)
        expect(owner.configured_self).to be(owner)
        expect(configured).to be(config)
      end

      it "treats direct instance variable assignments as configuration state" do
        config.configure { @tracked_files = "{app,lib}/**/*.rb" }

        expect(config.tracked_files).to eq("{app,lib}/**/*.rb")
      end

      it "evaluates __dir__ from the configuration block's source file" do
        expected_root = __dir__

        config.configure { root __dir__ }

        expect(config.root).to eq(expected_root)
      end

      it "reads existing configuration state instead of colliding caller variables" do
        owner = Object.new
        owner.instance_variable_set(:@root, "/caller/project")
        config.root("/real/project")
        observed_root = nil

        owner.instance_exec(config) do |target|
          # Direct ivar access is the behavior under test here.
          target.configure { observed_root = @root } # rubocop:disable RSpec/InstanceVariable
        end

        expect(observed_root).to eq(File.expand_path("/real/project"))
        expect(owner.instance_variable_get(:@root)).to eq("/caller/project")
      end

      it "derives cached configuration from the real configuration state" do
        owner = Object.new
        owner.instance_variable_set(:@root, "/wrong/project")
        config.root("/real/project")

        path = owner.instance_exec(config) do |target|
          target.configure do
            coverage_dir "cov"
            coverage_path
          end
          target.coverage_path
        end

        expect(path).to eq(File.expand_path("/real/project/cov"))
      end

      it "preserves block locals and block_given?" do
        owner_class = Class.new do
          def evaluate(target)
            local = :present
            variables = nil
            outer_result = yield
            target.configure { variables = [binding.local_variables, block_given?, local, outer_result] }
            variables
          end
        end

        variables, block_given, local, outer_result = owner_class.new.evaluate(config) { :outer }

        expect(variables).to include(:local, :variables)
        expect(block_given).to be true
        expect(local).to eq(:present)
        expect(outer_result).to eq(:outer)
      end

      it "resolves require_relative from the configuration source" do
        # An eval source under lib/ (not spec/) verifies require_relative's
        # base is the configuration source, not this spec. It must be a
        # file that exists: JRuby resolves the base through realpath.
        source_path = File.join(SimpleCov.root, "lib/simplecov.rb")
        # rubocop:disable Style/EvalWithLocation
        configuration = eval(<<~RUBY, binding, source_path, 1)
          proc { require_relative "simplecov/version" }
        RUBY
        # rubocop:enable Style/EvalWithLocation

        expect { config.configure(&configuration) }.not_to raise_error
      end

      it "keeps configuration exceptions anchored to their source" do
        source_path = File.join(SimpleCov.root, "lib/configuration_probe.rb")
        # rubocop:disable Style/EvalWithLocation
        configuration = eval(<<~RUBY, binding, source_path, 37)
          proc { raise "from config" }
        RUBY
        # rubocop:enable Style/EvalWithLocation

        expect { config.configure(&configuration) }.to raise_error("from config") do |error|
          expect(error.backtrace.first).to start_with("#{source_path}:37:")
        end
      end

      it "composes nested configuration blocks on the same target" do
        observed = nil

        config.configure do
          configure { @nested_state = :inner }
          observed = @nested_state # rubocop:disable RSpec/InstanceVariable
        end

        expect(observed).to eq(:inner)
        expect(config.instance_variable_get(:@nested_state)).to eq(:inner)
      end

      it "keeps nested configuration targets distinct" do
        other = config_class.new

        config.configure do
          @nested_state = :outer
          other.configure { @nested_state = :inner }
        end

        expect(config.instance_variable_get(:@nested_state)).to eq(:outer)
        expect(other.instance_variable_get(:@nested_state)).to eq(:inner)
      end

      it "works from frozen and immediate-value owners" do
        frozen_owner = Object.new.freeze
        frozen_self = nil
        immediate_self = nil

        frozen_owner.instance_exec(config) do |target|
          target.configure { |dsl| frozen_self = [self, dsl] }
        end
        1.instance_exec(config) do |target|
          target.configure { |dsl| immediate_self = [self, dsl] }
        end

        expect(frozen_self).to eq([frozen_owner, config])
        expect(immediate_self).to eq([1, config])
      end

      it "does not leak configuration commands onto the caller during evaluation" do
        owner = Object.new
        entered = Queue.new
        release = Queue.new
        worker = Thread.new do
          owner.instance_exec(config) do |target|
            target.configure do
              entered << true
              release.pop
            end
          end
        end

        entered.pop
        expect { owner.command_name("outside-thread") }.to raise_error(NoMethodError)
      ensure
        release << true if worker&.alive?
        worker&.join(2)
      end

      it "preserves the block error even when the target freezes itself" do
        disposable = config_class.new

        expect do
          disposable.configure do
            @new_configuration_state = :set
            freeze
            raise "original failure"
          end
        end.to raise_error("original failure")
      end

      it "preserves normal unknown-command behavior" do
        source_line = __LINE__ + 2

        expect { config.configure { unknown_configuration_command } }
          .to raise_error(NameError, /unknown_configuration_command/) do |error|
            expect(error.backtrace.first).to include("configuration_spec.rb:#{source_line}")
          end
      end
    end

    describe "#primary_coverage" do
      context "when branch coverage is enabled" do
        before { config.enable_coverage :branch }

        it "can set primary coverage to branch" do
          config.primary_coverage :branch

          expect(config.coverage_criteria).to contain_exactly :line, :branch
          expect(config.primary_coverage).to eq :branch
        end
      end

      context "when branch coverage is not enabled" do
        it "cannot set primary coverage to branch" do
          expect do
            config.primary_coverage :branch
          end.to raise_error(/branch.*disabled/i)
        end
      end

      it "can set primary coverage to line" do
        config.primary_coverage :line

        expect(config.coverage_criteria).to contain_exactly :line
        expect(config.primary_coverage).to eq :line
      end

      it "can set primary coverage to oneshot_line" do
        config.enable_coverage :oneshot_line
        config.primary_coverage :oneshot_line

        expect(config.coverage_criteria).to contain_exactly :oneshot_line
        expect(config.primary_coverage).to eq :oneshot_line
      end

      it "can't set primary coverage to arbitrary things" do
        expect do
          config.primary_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
      end
    end
  end
end
