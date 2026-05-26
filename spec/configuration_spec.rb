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

    context "when set via the legacy attr_writer" do
      before { config.print_error_status = false }

      it "reads back the assigned value" do
        expect(config.print_errors).to be false
      end
    end
  end

  describe "#print_error_status (deprecated)" do
    it "warns when read and still returns the value" do
      config.print_error_status = false
      value = nil
      stderr = capture_stderr { value = config.print_error_status }

      expect(value).to be false
      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`SimpleCov.print_error_status`")
      expect(stderr).to include("`SimpleCov.print_errors`")
    end

    it "returns the default (true) when nothing has been assigned" do
      value = nil
      capture_stderr { value = config.print_error_status }

      expect(value).to be true
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

  describe "#nocov_token" do
    it "warns of deprecation when called as a getter" do
      stderr = capture_stderr { config.nocov_token }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`SimpleCov.nocov_token`")
      expect(stderr).to include("`# simplecov:disable`")
      expect(stderr).to include("`# simplecov:enable`")
    end

    it "warns of deprecation when called as a setter" do
      stderr = capture_stderr { config.nocov_token("skippit") }

      expect(stderr).to include("[DEPRECATION]")
    end

    it "still returns the configured token (after the deprecation warning)" do
      capture_stderr { config.nocov_token("skippit") }
      value = nil
      stderr = capture_stderr { value = config.nocov_token }

      expect(value).to eq "skippit"
      expect(stderr).to include("[DEPRECATION]") # the read still warns
    end

    it "is aliased as #skip_token, which also warns" do
      stderr = capture_stderr { config.skip_token("skippit") }

      expect(stderr).to include("[DEPRECATION]")
      expect(config.current_nocov_token).to eq "skippit"
    end
  end

  describe "#current_nocov_token" do
    it "returns the configured token without emitting a deprecation warning" do
      value = nil
      stderr = capture_stderr { value = config.current_nocov_token }

      expect(value).to eq "nocov"
      expect(stderr).to be_empty
    end

    it "honours a value previously set via #nocov_token" do
      capture_stderr { config.nocov_token("skippit") }

      expect(config.current_nocov_token).to eq "skippit"
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

  describe "#tracked_files (deprecated)" do
    context "when configured" do
      let(:glob) { "{app,lib}/**/*.rb" }

      before { capture_stderr { config.track_files(glob) } }

      it "returns the configured glob" do
        expect(config.tracked_files).to eq glob
      end

      context "when configured again with nil" do
        before { capture_stderr { config.track_files(nil) } }

        it "returns nil" do
          expect(config.tracked_files).to be_nil
        end
      end
    end

    context "when unconfigured" do
      it "returns nil" do
        expect(config.tracked_files).to be_nil
      end
    end

    it "warns and names `cover` as the replacement when called" do
      stderr = capture_stderr { config.track_files("lib/**/*.rb") }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`SimpleCov.track_files`")
      expect(stderr).to include("`SimpleCov.cover \"lib/**/*.rb\"`")
    end

    # `track_files(nil)` clears the legacy glob, but `cover(nil)` raises —
    # don't point users at an invalid call. Copilot review on #1188.
    it "suggests cover_filters.clear when called with nil to clear the glob" do
      stderr = capture_stderr { config.track_files(nil) }

      expect(stderr).to include("[DEPRECATION]")
      expect(stderr).to include("`SimpleCov.cover_filters.clear`")
      expect(stderr).not_to include("`SimpleCov.cover nil`")
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
      it "is a non-warning alias for add_filter" do
        config.skip "lib/legacy"
        stderr = capture_stderr { config.skip "lib/another" }

        expect(stderr).to be_empty
        expect(config.filters.size).to eq 2
      end
    end

    describe "#add_filter (deprecated)" do
      it "warns and names `skip` as the replacement" do
        stderr = capture_stderr { config.add_filter "lib/legacy" }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.add_filter`")
        expect(stderr).to include("`SimpleCov.skip \"lib/legacy\"`")
        expect(config.filters.size).to eq 1
      end

      # The default warning interpolates `filter_argument.inspect`, which is
      # `nil` for the block form (`add_filter { ... }`); suggest the block
      # form spelling instead. Copilot review on #1188.
      it "suggests the block form when a block was given" do
        stderr = capture_stderr { config.add_filter { |sf| sf.filename.include?("legacy") } }

        expect(stderr).to include("`SimpleCov.skip { ... }`")
        expect(stderr).not_to include("nil")
      end
    end

    describe "#group" do
      it "is a non-warning alias for add_group" do
        stderr = capture_stderr { config.group "Models", "app/models" }

        expect(stderr).to be_empty
        expect(config.groups.keys).to eq ["Models"]
      end
    end

    describe "#add_group (deprecated)" do
      it "warns and names `group` as the replacement" do
        stderr = capture_stderr { config.add_group "Models", "app/models" }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.add_group`")
        expect(stderr).to include("`SimpleCov.group \"Models\", \"app/models\"`")
        expect(config.groups.keys).to eq ["Models"]
      end

      # `add_group "Name" { ... }` would otherwise display as
      # `SimpleCov.group "Name", nil`, dropping the block. Copilot review on #1188.
      it "suggests the block form when a block was given" do
        stderr = capture_stderr { config.add_group("Other") { |sf| sf.filename.include?("xyz") } }

        expect(stderr).to include("`SimpleCov.group \"Other\" { ... }`")
        expect(stderr).not_to include('"Other", nil')
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
        previous = config.instance_variable_get(:@use_merging)
        config.instance_variable_set(:@use_merging, nil)
        example.run
        config.instance_variable_set(:@use_merging, previous)
      end

      it "defaults to true" do
        expect(config.merging).to be true
      end

      it "stores the explicit false" do
        config.merging false
        expect(config.merging).to be false
      end
    end

    describe "#use_merging (deprecated)" do
      around do |example|
        previous = config.instance_variable_get(:@use_merging)
        config.instance_variable_set(:@use_merging, nil)
        example.run
        config.instance_variable_set(:@use_merging, previous)
      end

      it "warns and names `merging` as the replacement" do
        stderr = capture_stderr { config.use_merging(false) }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.use_merging`")
        expect(stderr).to include("`SimpleCov.merging`")
        expect(config.instance_variable_get(:@use_merging)).to be false
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

    describe "#enable_for_subprocesses (deprecated)" do
      it "warns and names `merge_subprocesses` as the replacement" do
        stderr = capture_stderr { config.enable_for_subprocesses(true) }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.enable_for_subprocesses`")
        expect(stderr).to include("`SimpleCov.merge_subprocesses`")
        expect(config.merge_subprocesses).to be true
      end

      it "returns the existing value when called with no argument after being set" do
        config.merge_subprocesses true
        value = nil
        capture_stderr { value = config.enable_for_subprocesses }

        expect(value).to be true
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

    describe "#enable_coverage_for_eval (deprecated)" do
      before { allow(config).to receive(:coverage_for_eval_supported?).and_return(true) }

      it "warns and still toggles the flag" do
        stderr = capture_stderr { config.enable_coverage_for_eval }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.enable_coverage_for_eval`")
        expect(stderr).to include("`SimpleCov.enable_coverage :eval`")
        expect(config.coverage_for_eval_enabled?).to be true
      end
    end

    shared_examples "setting coverage expectations" do |coverage_setting|
      after do
        config.clear_coverage_criteria
      end

      it "does not warn you about your usage" do
        allow(config).to receive(:warn)
        config.public_send(coverage_setting, 100.00)
        expect(config).not_to have_received(:warn)
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

    describe "#minimum_coverage_by_file" do
      it_behaves_like "setting coverage expectations", :minimum_coverage_by_file

      context "with per-path overrides" do
        after { config.clear_coverage_criteria }

        it "splits Symbol-keyed defaults from String-keyed overrides" do
          config.minimum_coverage_by_file line: 70, "app/critical.rb" => 100

          expect(config.minimum_coverage_by_file).to eq line: 70
          expect(config.minimum_coverage_by_file_overrides).to eq("app/critical.rb" => {line: 100})
        end

        it "normalizes a Numeric override into the primary criterion" do
          config.minimum_coverage_by_file "app/critical.rb" => 100

          expect(config.minimum_coverage_by_file).to eq({})
          expect(config.minimum_coverage_by_file_overrides).to eq("app/critical.rb" => {line: 100})
        end

        it "accepts a per-criterion Hash as an override value" do
          config.enable_coverage :branch
          config.minimum_coverage_by_file "app/critical.rb" => {line: 100, branch: 90}

          expect(config.minimum_coverage_by_file_overrides)
            .to eq("app/critical.rb" => {line: 100, branch: 90})
        end

        it "accepts Regexp keys" do
          config.minimum_coverage_by_file(%r{\Aapp/mailers/} => 100)

          expect(config.minimum_coverage_by_file_overrides).to eq(%r{\Aapp/mailers/} => {line: 100})
        end

        it "preserves the declaration order of overrides" do
          config.minimum_coverage_by_file(
            "lib/" => 80,
            "lib/critical.rb" => 100,
            %r{spec/} => 50
          )

          expect(config.minimum_coverage_by_file_overrides.keys)
            .to eq(["lib/", "lib/critical.rb", %r{spec/}])
        end

        it "raises when an override value uses an unsupported criterion" do
          expect do
            config.minimum_coverage_by_file "app/critical.rb" => {unknown: 100}
          end.to raise_error(/unsupported.*unknown/i)
        end

        it "raises when a key is neither Symbol nor String nor Regexp" do
          expect do
            config.minimum_coverage_by_file 42 => 100
          end.to raise_error(SimpleCov::ConfigurationError, /must be Symbol/)
        end
      end

      describe "#minimum_coverage_by_file_overrides" do
        it "defaults to an empty Hash" do
          expect(config.minimum_coverage_by_file_overrides).to eq({})
        end
      end
    end

    describe "#minimum_coverage_by_group" do
      after do
        config.clear_coverage_criteria
      end

      it "does not warn you about your usage" do
        allow(config).to receive(:warn)
        config.minimum_coverage_by_group({"Test Group 1" => 100.00})
        expect(config).not_to have_received(:warn)
      end

      it "warns you about your usage" do
        allow(config).to receive(:warn)
        config.minimum_coverage_by_group({"Test Group 1" => 100.01})
        expect(config).to have_received(:warn)
          .with("The coverage you set for minimum_coverage_by_group is greater than 100%")
      end

      it "sets the right coverage value when called with a number" do
        config.minimum_coverage_by_group({"Test Group 1" => 80})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {line: 80}})
      end

      it "sets the right coverage when called with a hash of just line" do
        config.minimum_coverage_by_group({"Test Group 1" => {line: 85.0}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {line: 85.0}})
      end

      it "sets the right coverage when called with a hash of just branch" do
        config.enable_coverage :branch
        config.minimum_coverage_by_group({"Test Group 1" => {branch: 85.0}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 85.0}})
      end

      it "sets the right coverage when called with both line and branch" do
        config.enable_coverage :branch
        config.minimum_coverage_by_group({"Test Group 1" => {branch: 85.0, line: 95.4}})

        expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 85.0, line: 95.4}})
      end

      it "raises when trying to set branch coverage but not enabled" do
        expect do
          config.minimum_coverage_by_group({"Test Group 1" => {branch: 42}})
        end.to raise_error(/branch.*disabled/i)
      end

      it "raises when unknown coverage criteria provided" do
        expect do
          config.minimum_coverage_by_group({"Test Group 1" => {unknown: 42}})
        end.to raise_error(/unsupported.*unknown/i)
      end

      context "when primary coverage is set" do
        before do
          config.enable_coverage :branch
          config.primary_coverage :branch
        end

        it "sets the right coverage value when called with a number" do
          config.minimum_coverage_by_group({"Test Group 1" => 80})

          expect(config.minimum_coverage_by_group).to eq({"Test Group 1" => {branch: 80}})
        end
      end
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

    describe "#coverage_criterion" do
      it "defaults to line" do
        expect(config.coverage_criterion).to eq :line
      end

      it "works fine with line" do
        config.coverage_criterion :line

        expect(config.coverage_criterion).to eq :line
      end

      it "works fine with :branch" do
        config.coverage_criterion :branch

        expect(config.coverage_criterion).to eq :branch
      end

      it "works fine setting it back and forth" do
        config.coverage_criterion :branch
        config.coverage_criterion :line

        expect(config.coverage_criterion).to eq :line
      end

      it "errors out on unknown coverage" do
        expect do
          config.coverage_criterion :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
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

      it "can't enable arbitrary things" do
        expect do
          config.enable_coverage :unknown
        end.to raise_error(/unsupported.*unknown.*line/i)
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

    describe "#branch_coverage?", if: SimpleCov.branch_coverage_supported? do
      it "returns true of branch coverage is being measured" do
        config.enable_coverage :branch

        expect(config).to be_branch_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_branch_coverage
      end
    end

    describe "#method_coverage?", if: SimpleCov.method_coverage_supported? do
      it "returns true if method coverage is being measured" do
        config.enable_coverage :method

        expect(config).to be_method_coverage
      end

      it "returns false for line coverage" do
        config.coverage_criterion :line

        expect(config).not_to be_method_coverage
      end
    end

    describe "#enable_coverage with :method" do
      it "can enable method coverage" do
        config.enable_coverage :method

        expect(config.coverage_criteria).to contain_exactly :line, :method
      end
    end

    describe "#coverage_criterion with :method" do
      it "works fine with :method" do
        config.coverage_criterion :method

        expect(config.coverage_criterion).to eq :method
      end
    end

    describe "#enable_for_subprocesses (deprecated, still functional)" do
      it "returns false by default" do
        capture_stderr { expect(config.enable_for_subprocesses).to be false }
      end

      it "can be set to true (deprecation warning notwithstanding)" do
        capture_stderr { config.enable_for_subprocesses true }
        expect(config.merge_subprocesses).to be true
      end

      it "can be enabled and then disabled again" do
        capture_stderr do
          config.enable_for_subprocesses true
          config.enable_for_subprocesses false
        end
        expect(config.merge_subprocesses).to be false
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
    end

    describe "#at_exit" do
      around do |example|
        previous = config.instance_variable_get(:@at_exit)
        config.instance_variable_set(:@at_exit, nil)
        example.run
        config.instance_variable_set(:@at_exit, previous)
      end

      it "returns a default proc (formats the result) when called with no block while Coverage is running" do
        allow(Coverage).to receive(:running?).and_return(true)
        proc_returned = config.at_exit
        expect(proc_returned).to be_a(Proc)
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

        SimpleCov.at_fork.call(12_345)

        expect(SimpleCov).to have_received(:command_name).with(/subprocess: 12345/)
        expect(SimpleCov).to have_received(:print_errors).with(false)
        expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
        expect(SimpleCov).to have_received(:minimum_coverage).with(0)
        expect(SimpleCov).to have_received(:start)
      end
    end

    describe "#command_name" do
      after { config.instance_variable_set(:@name, nil) }

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

    describe "#parse_filter" do
      it "raises when given neither a filter argument nor a block" do
        expect { config.send(:parse_filter) }.to raise_error(ArgumentError, /filter or a block/)
      end
    end

    describe "#configure" do
      it "uses instance_exec directly when the block is in our own context" do
        # Stub equal? so the "block defined in our own context" branch fires
        # without contorting the test to share a binding with the config.
        allow(config).to receive(:equal?).and_return(true)
        config.configure { @configured = true }
        expect(config.instance_variable_get(:@configured)).to be true
      end
    end

    describe "#use_merging (deprecated, still functional)" do
      around do |example|
        previous = config.instance_variable_get(:@use_merging)
        config.instance_variable_set(:@use_merging, nil)
        example.run
        config.instance_variable_set(:@use_merging, previous)
      end

      it "stores the explicit value when given true" do
        capture_stderr { config.use_merging(true) }
        expect(config.instance_variable_get(:@use_merging)).to be true
      end

      it "stores the explicit value when given false" do
        capture_stderr { config.use_merging(false) }
        expect(config.instance_variable_get(:@use_merging)).to be false
      end

      it "defaults to true when never set" do
        capture_stderr { expect(config.use_merging).to be true }
      end
    end

    describe "#enable_coverage_for_eval (deprecated, still functional)" do
      context "when the runtime does not support eval coverage" do
        before { allow(config).to receive(:coverage_for_eval_supported?).and_return(false) }

        it "leaves the flag false and warns about unsupported runtime" do
          stderr = capture_stderr { config.enable_coverage_for_eval }

          expect(config.coverage_for_eval_enabled?).to be false
          expect(stderr).to include("Coverage for eval is not available")
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
