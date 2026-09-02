# frozen_string_literal: true

require "helper"
require "coverage"

RSpec.describe SimpleCov::Configuration do
  # Puts back the destination settings an example wrote, so the next one starts
  # from a configuration that was never told where to write.
  def forget_destination
    %i[@root @coverage_dir @coverage_path @coverage_dir_explicit @coverage_path_explicit].each do |ivar|
      config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
    end
  end

  let(:config_class) do
    Class.new do
      include SimpleCov::Configuration
    end
  end
  let(:config) { config_class.new }

  describe "explicit writers" do
    it "writes root expanded" do
      config.root = "tmp/project"

      expect(config.root).to eq(File.expand_path("tmp/project"))
    end

    it "re-derives the coverage path from it" do
      config.root = "tmp/project"

      expect(config.coverage_path).to eq(File.expand_path("coverage", config.root))
    end

    it "resets root to the working directory when written nil" do
      config.root = nil

      expect(config.root).to eq(File.expand_path(Dir.getwd))
    end

    it "writes the coverage directory" do
      config.root = "tmp/project"
      config.coverage_dir = "cov"

      expect(config.coverage_dir).to eq("cov")
    end

    it "re-derives the path from it" do
      config.root = "tmp/project"
      config.coverage_dir = "cov"

      expect(config.coverage_path).to eq(File.expand_path("cov", config.root))
    end

    it "writes an explicit coverage path, expanded" do
      Dir.mktmpdir do |tmp|
        config.coverage_path = File.join(tmp, "out")

        expect(config.coverage_path).to eq(File.join(tmp, "out"))
      end
    end

    it "creates the directory it names" do
      Dir.mktmpdir do |tmp|
        config.coverage_path = File.join(tmp, "out")

        expect(File).to be_directory(File.join(tmp, "out"))
      end
    end

    it "keeps an explicitly written coverage path across a later root change" do
      Dir.mktmpdir do |tmp|
        config.coverage_path = File.join(tmp, "out")
        config.root = "somewhere/else"

        expect(config.coverage_path).to eq(File.join(tmp, "out"))
      end
    end

    it "writes the command name" do
      config.command_name = "Unit Tests"

      expect(config.command_name).to eq("Unit Tests")
    end

    it "writes the primary coverage criterion it validates" do
      config.enable_coverage :branch
      config.primary_coverage = :branch

      expect(config.primary_coverage).to eq(:branch)
    ensure
      config.clear_coverage_criteria
    end

    it "refuses a primary criterion that is not enabled" do
      expect { config.primary_coverage = :branch }.to raise_error(/branch/)
    end

    it "writes color" do
      config.color = :never

      expect(config.color).to eq(:never)
    end

    it "writes print_errors" do
      config.print_errors = false

      expect(config.print_errors).to be(false)
    end

    it "writes source_in_json" do
      config.source_in_json = false

      expect(config.source_in_json).to be(false)
    end

    it "writes parallel_tests" do
      config.parallel_tests = false

      expect(config.parallel_tests).to be(false)
    end

    it "writes merge_subprocesses, with false standing in for nothing" do
      config.merge_subprocesses = nil

      expect(config.merge_subprocesses).to be(false)
    end

    it "writes merging" do
      config.merging = false

      expect(config.merging).to be(false)
    end

    it "writes finalize_merge as the explicit answer it is" do
      config.finalize_merge = false

      expect(config.finalize_merge?).to be(false)
    end

    it "writes merge_timeout, ignoring anything but an Integer" do
      config.merge_timeout = 300
      config.merge_timeout = "9"

      expect(config.merge_timeout).to eq(300)
    end

    it "writes parallel_wait_timeout, ignoring anything but an Integer" do
      config.parallel_wait_timeout = 90
      config.parallel_wait_timeout = "9"

      expect(config.parallel_wait_timeout).to eq(90)
    end

    it "writes the baseline file path" do
      config.baseline_file = "config/floors.yml"

      expect(config.baseline_file).to eq("config/floors.yml")
    end

    it "writes a history limit it validates" do
      config.history_limit = 5

      expect(config.history_limit).to eq(5)
    end

    it "refuses a history limit below zero" do
      expect { config.history_limit = -1 }.to raise_error(SimpleCov::ConfigurationError, /non-negative/)
    end

    it "writes production_coverage expanded against the root" do
      config.production_coverage = "tmp/production.json"

      expect(config.production_coverage).to eq(File.expand_path("tmp/production.json", config.root))
    end

    it "answers the stored baseline file when writing through the dual method" do
      expect(config.baseline_file("config/floors.yml")).to eq("config/floors.yml")
    end

    it "answers the stored history limit when writing through the dual method" do
      expect(config.history_limit(5)).to eq(5)
    end

    it "answers the stored production store, expanded, when writing through the dual method" do
      expect(config.production_coverage("tmp/production.json"))
        .to eq(File.expand_path("tmp/production.json", config.root))
    end

    it "refuses a production_coverage that is not a path" do
      expect { config.production_coverage = 42 }.to raise_error(SimpleCov::ConfigurationError, /path/)
    end
  end

  describe "#load_coverage" do
    it "answers what require answers" do
      allow(config).to receive(:require).and_return(false)

      expect(config.send(:load_coverage)).to be(false)
    end

    it "requires the stdlib Coverage library" do
      allow(config).to receive(:require).and_return(false)
      config.send(:load_coverage)

      expect(config).to have_received(:require).with("coverage")
    end
  end

  describe "#require_html_formatter" do
    it "requires the bundled HTML formatter when :html is asked for" do
      allow(config).to receive(:require_relative)

      config.send(:require_html_formatter, :html)

      expect(config).to have_received(:require_relative).with("../../simplecov-html")
    end

    it "requires nothing for a format the core already carries" do
      allow(config).to receive(:require_relative)

      config.send(:require_html_formatter, :json)

      expect(config).not_to have_received(:require_relative)
    end
  end

  describe "#coverage" do
    after { config.clear_coverage_criteria }

    it "answers the criterion it configured" do
      expect(config.coverage(:branch)).to eq(:branch)
    end

    it "answers the oneshot criterion under its own name" do
      expect(config.coverage(:line, oneshot: true)).to eq(:oneshot_line)
    end

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

      it "rejects thresholds for :eval with a message about thresholds, not the criterion" do
        allow(config).to receive(:coverage_for_eval_supported?).and_return(true)

        expect { config.coverage :eval, minimum: 100 }
          .to raise_error(SimpleCov::ConfigurationError, /:eval only toggles measuring eval'd code/)
      end
    end

    describe "per-group thresholds (per: group targets)" do
      it "stores a per-criterion minimum under the named group" do
        config.coverage(:line) { minimum 95, per: group("Models") }
        config.coverage(:branch) { minimum 90, per: group("Models") }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95, branch: 90})
      end

      it "normalizes a Symbol group name to match Symbol-defined groups" do
        config.coverage(:line) { minimum 95, per: group(:Models) }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95})
      end
    end

    describe "the deprecated suffixed scope verbs" do
      it "warns with the per: replacement for minimum_per_file" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_file 80 } }

        expect(stderr).to include("[DEPRECATION]").and include("`minimum 80, per: :file`")
      end

      it "still stores what minimum_per_file was given" do
        capture_stderr { config.coverage(:line) { minimum_per_file 80 } }

        expect(config.minimum_coverage_by_file).to eq(line: 80)
      end

      it "suggests the path target for minimum_per_file with only:" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_file 100, only: "app/x.rb" } }

        expect(stderr).to include(%(`minimum 100, per: "app/x.rb"`))
      end

      it "still stores the per-file floor it was given" do
        capture_stderr { config.coverage(:line) { minimum_per_file 100, only: "app/x.rb" } }

        expect(config.minimum_coverage_by_file_overrides).to eq("app/x.rb" => {line: 100})
      end

      it "warns with the group target replacement for minimum_per_group" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_group 95, only: "Models" } }

        expect(stderr).to include(%(`minimum 95, per: group("Models")`))
      end

      it "still stores what minimum_per_group was given" do
        capture_stderr { config.coverage(:line) { minimum_per_group 95, only: "Models" } }

        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95})
      end

      it "warns for the maximum_missed_per_file keyword form" do
        stderr = capture_stderr { config.coverage :line, maximum_missed_per_file: 5 }

        expect(stderr).to include("`maximum_missed 5, per: :file`")
      end

      it "still stores the missed-per-file cap it was given" do
        capture_stderr { config.coverage :line, maximum_missed_per_file: 5 }

        expect(config.maximum_missed_per_file).to eq(line: 5)
      end

      it "refuses a per-file floor for a criterion that is not enabled" do
        expect { config.send(:store_minimum_per_file, :branch, 80, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
      end

      it "warns about a per-file floor above what coverage can reach" do
        stderr = capture_stderr { config.send(:store_minimum_per_file, :line, 101, nil) }

        expect(stderr).to eq("The coverage you set for minimum_coverage_by_file is greater than 100%\n")
      end

      it "refuses a per-file miss cap for a criterion that is not enabled" do
        expect { config.send(:store_maximum_missed_per_file, :branch, 5, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
      end

      [-1, 1.5].each do |cap|
        it "refuses #{cap.inspect}, which is not a count of misses" do
          expect { config.send(:store_maximum_missed_per_file, :line, cap, nil) }
            .to raise_error(SimpleCov::ConfigurationError, /non-negative integer count/)
        end
      end

      it "minimum_per_file still rejects a non-String/Regexp only: target" do
        capture_stderr do
          expect { config.coverage(:line) { minimum_per_file 100, only: :line } }
            .to raise_error(SimpleCov::ConfigurationError, /must be a String path or Regexp/)
        end
      end
    end
  end

  describe "#coverage overall thresholds" do
    after { config.clear_coverage_criteria }

    context "with the one-liner form" do
      before { config.coverage :branch, minimum: 80, maximum: 95, maximum_drop: 5 }

      it "stores the per-criterion minimum" do
        expect(config.minimum_coverage).to eq(branch: 80)
      end

      it "stores the per-criterion maximum" do
        expect(config.maximum_coverage).to eq(branch: 95)
      end

      it "stores the per-criterion drop" do
        expect(config.maximum_coverage_drop).to eq(branch: 5)
      end
    end

    context "with the block form" do
      before do
        config.coverage :line do
          minimum 90
          maximum_drop 5
        end
      end

      it "stores the minimum" do
        expect(config.minimum_coverage).to eq(line: 90)
      end

      it "stores the drop" do
        expect(config.maximum_coverage_drop).to eq(line: 5)
      end
    end

    context "with exact" do
      before { config.coverage :line, exact: 95 }

      it "pins the minimum" do
        expect(config.minimum_coverage).to eq(line: 95)
      end

      it "pins the maximum to it too" do
        expect(config.maximum_coverage).to eq(line: 95)
      end
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

  describe "#coverage per-file thresholds (per: :file and path targets)" do
    after { config.clear_coverage_criteria }

    it "sets a default applied to every file" do
      config.coverage(:line) { minimum 80, per: :file }
      expect(config.minimum_coverage_by_file).to eq(line: 80)
    end

    context "with a String path and a Regexp target" do
      before do
        config.coverage :line do
          minimum 80, per: :file
          minimum 100, per: "app/mailers/request_mailer.rb"
          minimum 95, per: %r{\Aapp/payments/}
        end
      end

      it "keeps the per-file default" do
        expect(config.minimum_coverage_by_file).to eq(line: 80)
      end

      it "overrides it for each target" do
        expect(config.minimum_coverage_by_file_overrides).to eq(
          "app/mailers/request_mailer.rb" => {line: 100},
          %r{\Aapp/payments/} => {line: 95}
        )
      end
    end

    it "keeps line and branch overrides for the same path independent" do
      config.coverage(:line) { minimum 100, per: "app/x.rb" }
      config.coverage(:branch) { minimum 90, per: "app/x.rb" }
      expect(config.minimum_coverage_by_file_overrides).to eq("app/x.rb" => {line: 100, branch: 90})
    end

    it "rejects a per: target it cannot read as a scope" do
      expect { config.coverage(:line) { minimum 100, per: 42 } }
        .to raise_error(SimpleCov::ConfigurationError, /`per:` must be :file, a String path, a Regexp/)
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

    context "when set via the legacy attr_writer" do
      before { config.print_error_status = false }

      it "reads back the assigned value" do
        expect(config.print_errors).to be false
      end
    end

    it "switches back on after being switched off" do
      config.print_errors false
      config.print_errors true
      expect(config.print_errors).to be true
    end
  end

  describe "#production_coverage" do
    it "defaults to nil" do
      expect(config.production_coverage).to be_nil
    end

    it "answers the stored, expanded path when writing" do
      expect(config.production_coverage("tmp/production.json"))
        .to eq(File.expand_path("tmp/production.json", config.root))
    end

    it "takes a String subclass" do
      config.production_coverage Class.new(String).new("tmp/production.json")

      expect(config.production_coverage).to eq(File.expand_path("tmp/production.json"))
    end

    it "stores the path, expanded against the root" do
      config.production_coverage "tmp/production.json"
      expect(config.production_coverage).to eq(File.expand_path("tmp/production.json", config.root))
    end

    it "keeps an absolute path as given" do
      absolute = File.expand_path("/var/data/production.json")
      config.production_coverage absolute
      expect(config.production_coverage).to eq(absolute)
    end

    it "rejects a non-string path" do
      expect { config.production_coverage 42 }
        .to raise_error(SimpleCov::ConfigurationError, "production_coverage takes a path, got 42")
    end

    it "names the value it refused, as written" do
      expect { config.production_coverage(:store) }
        .to raise_error(SimpleCov::ConfigurationError, "production_coverage takes a path, got :store")
    end

    it "keeps a stored path when read again" do
      config.production_coverage "tmp/production.json"
      stored = config.production_coverage
      expect(config.production_coverage).to eq(stored)
    end

    it "expands against the root in force at the time it is set" do
      config.root("/one")
      config.production_coverage "prod.json"
      config.root("/two")
      expect(config.production_coverage).to eq(File.expand_path("/one/prod.json"))
    end

    it "replaces a stored path with a later one" do
      config.production_coverage "first.json"
      config.production_coverage "second.json"
      expect(config.production_coverage).to eq(File.expand_path("second.json", config.root))
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

  describe "#print_error_status (deprecated)" do
    it "still returns the value when read" do
      config.print_error_status = false

      expect(without_stderr { config.print_error_status }).to be false
    end

    it "names itself in the deprecation it warns with" do
      config.print_error_status = false

      expect(capture_stderr { config.print_error_status })
        .to include("[DEPRECATION]").and include("`SimpleCov.print_error_status`")
    end

    it "names its replacement" do
      config.print_error_status = false

      expect(capture_stderr { config.print_error_status }).to include("`SimpleCov.print_errors`")
    end

    it "returns the default (true) when nothing has been assigned" do
      value = nil
      capture_stderr { value = config.print_error_status }

      expect(value).to be true
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

  describe "#clear_coverage_criteria" do
    it "puts the criteria back to the lazy default, not only the primary one" do
      config.enable_coverage :branch

      config.clear_coverage_criteria

      expect(config.coverage_criteria).to eq(Set[:line])
    end

    it "puts the leading criterion back as well" do
      config.enable_coverage :branch
      config.primary_coverage :branch

      config.clear_coverage_criteria

      expect(config.primary_coverage).to eq(:line)
    end
  end

  describe "#coverage_criterion_supported?" do
    it "loads Coverage before asking it anything" do
      allow(config).to receive(:load_coverage).and_call_original

      config.coverage_criterion_supported?(:branches)

      expect(config).to have_received(:load_coverage)
    end

    [true, false].each do |supported|
      it "answers #{supported}, whatever the runtime says" do
        allow(Coverage).to receive(:supported?).with(:branches).and_return(supported)

        expect(config.coverage_criterion_supported?(:branches)).to be supported
      end
    end

    context "when the runtime cannot be asked" do
      before do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:supported?).and_return(false)
      end

      %i[line branch].each do |criterion|
        it "supports #{criterion} coverage" do
          stub_const("RUBY_ENGINE", "ruby")

          expect(config.coverage_criterion_supported?(criterion)).to be true
        end
      end

      it "does not support eval" do
        expect(config.coverage_criterion_supported?(:eval)).to be false
      end

      %i[line eval].each do |criterion|
        it "supports no #{criterion} coverage on JRuby, which never emitted this data" do
          stub_const("RUBY_ENGINE", "jruby")

          expect(config.coverage_criterion_supported?(criterion)).to be false
        end
      end
    end
  end

  describe "#project_name" do
    after { config.instance_variable_set(:@project_name, nil) }

    it "uses the basename of the configured root, capitalized" do
      config.root("/Users/erik/Code/my_app")
      expect(config.project_name).to eq("My app")
    end

    it "does not raise when root is the filesystem root" do
      config.root("/")
      expect { config.project_name }.not_to raise_error
    end

    it "spaces every underscore and leaves the rest of the case alone" do
      config.root("/Code/my_awesome_API_app")
      expect(config.project_name).to eq("My awesome api app")
    end

    it "answers a name given to it" do
      config.root("/Code/my_app")

      expect(config.project_name("Chosen")).to eq("Chosen")
    end

    it "keeps it" do
      config.root("/Code/my_app")
      config.project_name("Chosen")

      expect(config.project_name).to eq("Chosen")
    end

    [nil, :symbol].each do |non_name|
      it "keeps the name it was given when handed #{non_name.inspect}" do
        config.project_name("Chosen")

        expect(config.project_name(non_name)).to eq("Chosen")
      end
    end

    it "keeps it when read again" do
      config.project_name("Chosen")
      config.project_name(nil)

      expect(config.project_name).to eq("Chosen")
    end

    it "derives a name once and keeps answering with it" do
      config.root("/Code/my_app")
      derived = config.project_name
      config.root("/Code/other_app")
      expect(config.project_name).to eq(derived)
    end

    it "takes a name given as a String subclass" do
      config.project_name(Class.new(String).new("Chosen"))

      expect(config.project_name).to eq("Chosen")
    end

    it "derives a name from the root" do
      config.root("/Code/my_app")

      expect(config.project_name).to eq("My app")
    end

    it "renames over the derived one" do
      config.root("/Code/my_app")
      config.project_name

      expect(config.project_name("Renamed")).to eq("Renamed")
    end

    it "stores an explicit name" do
      config.project_name("Custom")
      expect(config.project_name).to eq("Custom")
    end
  end

  describe "#nocov_token" do
    it "names itself in the deprecation it warns with when called as a getter" do
      expect(capture_stderr { config.nocov_token })
        .to include("[DEPRECATION]").and include("`SimpleCov.nocov_token`")
    end

    it "names the directives that replace it" do
      expect(capture_stderr { config.nocov_token })
        .to include("`# simplecov:disable`").and include("`# simplecov:enable`")
    end

    it "warns of deprecation when called as a setter" do
      stderr = capture_stderr { config.nocov_token("skippit") }

      expect(stderr).to include("[DEPRECATION]")
    end

    it "still returns the configured token" do
      capture_stderr { config.nocov_token("skippit") }

      expect(without_stderr { config.nocov_token }).to eq "skippit"
    end

    it "warns on the way" do
      capture_stderr { config.nocov_token("skippit") }

      expect(capture_stderr { config.nocov_token }).to include("[DEPRECATION]")
    end

    it "warns under its #skip_token alias too" do
      expect(capture_stderr { config.skip_token("skippit") }).to include("[DEPRECATION]")
    end

    it "still stores what #skip_token was given" do
      capture_stderr { config.skip_token("skippit") }

      expect(config.current_nocov_token).to eq "skippit"
    end
  end

  describe "#current_nocov_token" do
    it "returns the configured token" do
      expect(without_stderr { config.current_nocov_token }).to eq "nocov"
    end

    it "emits no deprecation warning" do
      expect(capture_stderr { config.current_nocov_token }).to be_empty
    end

    it "honours a value previously set via #nocov_token" do
      capture_stderr { config.current_nocov_token("skippit") }

      expect(config.current_nocov_token).to eq "skippit"
    end

    it "answers the token that replaces one already set" do
      config.current_nocov_token("first")

      expect(config.current_nocov_token("second")).to eq "second"
    end

    it "keeps the replacement" do
      config.current_nocov_token("first")
      config.current_nocov_token("second")

      expect(config.current_nocov_token).to eq "second"
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

    it "drops a path it had already derived when the directory changes under it" do
      config.coverage_path
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
        Dir.mktmpdir { |other_root| config.root(other_root) }

        expect(config.coverage_path).to eq(out)
      end
    end

    it "expands a relative explicit path against the current working directory" do
      Dir.mktmpdir do |cwd|
        Dir.chdir(cwd) { config.coverage_path("build/cov") }

        expect(config.coverage_path).to eq(File.join(File.realpath(cwd), "build/cov"))
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
    end

    context "when configured and then configured again with nil" do
      before do
        capture_stderr { config.track_files("{app,lib}/**/*.rb") }
        capture_stderr { config.track_files(nil) }
      end

      it "returns nil" do
        expect(config.tracked_files).to be_nil
      end
    end

    context "when unconfigured" do
      it "returns nil" do
        expect(config.tracked_files).to be_nil
      end
    end

    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.track_files("lib/**/*.rb") })
        .to include("[DEPRECATION]").and include("`SimpleCov.track_files`")
    end

    it "names `cover` as the replacement" do
      expect(capture_stderr { config.track_files("lib/**/*.rb") })
        .to include("`SimpleCov.cover \"lib/**/*.rb\"`")
    end

    it "suggests cover_filters.clear when called with nil to clear the glob" do
      expect(capture_stderr { config.track_files(nil) })
        .to include("[DEPRECATION]").and include("`SimpleCov.cover_filters.clear`")
    end

    it "suggests no call that would store the nil" do
      expect(capture_stderr { config.track_files(nil) }).not_to include("`SimpleCov.cover nil`")
    end
  end

  describe "#cover" do
    context "with a string glob" do
      before { config.cover "lib/**/*.rb" }

      it "stores one filter" do
        expect(config.cover_filters.size).to eq 1
      end

      it "stores it as a GlobFilter" do
        expect(config.cover_filters.first).to be_a(SimpleCov::GlobFilter)
      end

      it "answers the glob it was given" do
        expect(config.cover_globs).to eq ["lib/**/*.rb"]
      end
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

    it "hands the block to the predicate filter" do
      predicate = proc { |sf| sf.filename.end_with?("foo.rb") }
      config.cover(&predicate)

      expect(config.cover_filters.first.filter_argument).to equal(predicate)
    end

    it "answers the cover filters it holds" do
      expect(config.cover("lib/**/*.rb")).to equal(config.cover_filters)
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
    it "warns about nothing, unlike add_filter" do
      config.skip "lib/legacy"

      expect(capture_stderr { config.skip "lib/another" }).to be_empty
    end

    it "stores a filter for each call" do
      config.skip "lib/legacy"
      config.skip "lib/another"

      expect(config.filters.size).to eq 2
    end

    it "stores a String as a path filter" do
      config.skip "lib/legacy"

      expect(config.filters.last).to be_a(SimpleCov::StringFilter)
    end

    it "stores a block as a predicate filter" do
      predicate = proc { |sf| sf.filename.include?("legacy") }
      config.skip(&predicate)

      expect(config.filters.last).to be_a(SimpleCov::BlockFilter)
    end
  end

  describe "#add_filter (deprecated)" do
    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.add_filter "lib/legacy" })
        .to include("[DEPRECATION]").and include("`SimpleCov.add_filter`")
    end

    it "names `skip` as the replacement" do
      expect(capture_stderr { config.add_filter "lib/legacy" }).to include("`SimpleCov.skip \"lib/legacy\"`")
    end

    it "still stores the filter" do
      capture_stderr { config.add_filter "lib/legacy" }

      expect(config.filters.size).to eq 1
    end

    it "suggests the block form when a block was given" do
      expect(capture_stderr { config.add_filter { |sf| sf.filename.include?("legacy") } })
        .to include("`SimpleCov.skip { ... }`")
    end

    it "names no argument it was not given" do
      expect(capture_stderr { config.add_filter { |sf| sf.filename.include?("legacy") } })
        .not_to include("nil")
    end
  end

  describe "#group" do
    it "warns about nothing, unlike add_group" do
      expect(capture_stderr { config.group "Models", "app/models" }).to be_empty
    end

    it "stores the group" do
      config.group "Models", "app/models"

      expect(config.groups.keys).to eq ["Models"]
    end

    it "stores the filter it was given under the name" do
      config.group "Models", "app/models"

      expect(config.groups["Models"]).to be_a(SimpleCov::StringFilter)
    end

    it "takes a block as the group's filter" do
      config.group("Models") { |sf| sf.filename.include?("models") }

      expect(config.groups["Models"]).to be_a(SimpleCov::BlockFilter)
    end

    it "reserves Ungrouped for files that match no configured group" do
      config.group "Models", "app/models"

      expect { config.group "Ungrouped", // }
        .to raise_error(SimpleCov::ConfigurationError,
          %("Ungrouped" is reserved for files that do not match a configured group))
    end

    it "leaves the groups it already had alone after refusing the reserved name" do
      config.group "Models", "app/models"
      suppress(SimpleCov::ConfigurationError) { config.group "Ungrouped", // }

      expect(config.groups.keys).to eq ["Models"]
    end

    it "rejects the reserved name when replacing the groups hash" do
      config.group "Models", "app/models"

      expect { config.groups = {"Ungrouped" => SimpleCov::StringFilter.new("lib")} }
        .to raise_error(SimpleCov::ConfigurationError, /reserved/)
    end

    it "leaves the groups it already had alone after refusing the replacement hash" do
      config.group "Models", "app/models"
      suppress(SimpleCov::ConfigurationError) do
        config.groups = {"Ungrouped" => SimpleCov::StringFilter.new("lib")}
      end

      expect(config.groups.keys).to eq ["Models"]
    end

    it "normalizes a Symbol group name to its String spelling" do
      config.group :Models, "app/models"

      expect(config.groups.keys).to eq ["Models"]
    end

    it "keeps a Symbol spelling from bypassing the reserved name" do
      expect { config.group :Ungrouped, // }
        .to raise_error(SimpleCov::ConfigurationError, /reserved/)
    end

    it "stores no group for the Symbol spelling" do
      suppress(SimpleCov::ConfigurationError) { config.group :Ungrouped, // }

      expect(config.groups).to be_empty
    end

    it "rejects group names that are neither String nor Symbol" do
      expect { config.group 42, // }
        .to raise_error(SimpleCov::ConfigurationError, "Group names must be Strings, got 42 (Integer)")
    end

    it "names the rejected value and its class, inspecting the value" do
      expect { config.group nil, // }
        .to raise_error(SimpleCov::ConfigurationError, "Group names must be Strings, got nil (NilClass)")
    end

    it "stores no group for one" do
      suppress(SimpleCov::ConfigurationError) { config.group 42, // }

      expect(config.groups).to be_empty
    end

    it "stores no group for a name that is nothing at all" do
      suppress(SimpleCov::ConfigurationError) { config.group nil, // }

      expect(config.groups).to be_empty
    end

    it "normalizes Symbol keys when replacing the groups hash" do
      config.groups = {Models: SimpleCov::StringFilter.new("app/models")}

      expect(config.groups.keys).to eq ["Models"]
    end

    it "rejects a Symbol spelling of the reserved name in a replacement hash" do
      expect { config.groups = {Ungrouped: SimpleCov::StringFilter.new("lib")} }
        .to raise_error(SimpleCov::ConfigurationError, /reserved/)
    end

    it "stores no group from one" do
      suppress(SimpleCov::ConfigurationError) do
        config.groups = {Ungrouped: SimpleCov::StringFilter.new("lib")}
      end

      expect(config.groups).to be_empty
    end
  end

  describe "#add_group (deprecated)" do
    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.add_group "Models", "app/models" })
        .to include("[DEPRECATION]").and include("`SimpleCov.add_group`")
    end

    it "names `group` as the replacement" do
      expect(capture_stderr { config.add_group "Models", "app/models" })
        .to include("`SimpleCov.group \"Models\", \"app/models\"`")
    end

    it "still stores the group" do
      capture_stderr { config.add_group "Models", "app/models" }

      expect(config.groups.keys).to eq ["Models"]
    end

    it "suggests the block form when a block was given" do
      expect(capture_stderr { config.add_group("Other") { |sf| sf.filename.include?("xyz") } })
        .to include("`SimpleCov.group \"Other\" { ... }`")
    end

    it "names no argument it was not given" do
      expect(capture_stderr { config.add_group("Other") { |sf| sf.filename.include?("xyz") } })
        .not_to include('"Other", nil')
    end

    it "rejects the reserved Ungrouped name" do
      expect { capture_stderr { config.add_group "Ungrouped", // } }
        .to raise_error(SimpleCov::ConfigurationError, /reserved/)
    end

    it "stores no group for it" do
      suppress(SimpleCov::ConfigurationError) { capture_stderr { config.add_group "Ungrouped", // } }

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

    [false, true].each do |final|
      it "answers #{final} for a process that is #{final ? "the" : "not the"} final one" do
        config.finalize_merge true
        allow(config).to receive_messages(collating_result?: false, final_result_process?: final)

        expect(config.merge_finalization_owner?).to be final
      end
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

    context "with externally finalized parallel resultsets" do
      before { configure_parallel_worker(adapter) }

      it "infers false" do
        expect(without_stderr { config.finalize_merge }).to be false
      end

      it "says what it inferred" do
        expect(capture_stderr { config.finalize_merge })
          .to include("SimpleCov inferred `finalize_merge false`")
      end

      it "names both settings that would say so outright" do
        expect(capture_stderr { config.finalize_merge })
          .to include("`SimpleCov.finalize_merge false`").and include("`SimpleCov.finalize_merge true`")
      end

      it "points at the documentation" do
        expect(capture_stderr { config.finalize_merge }).to include("#merge-finalization-ownership")
      end
    end

    # Puts the configuration in the shape a parallel worker writing to its own
    # destination leaves it in.
    def configure_parallel_worker(current, groups: "3", dir: "coverage/turbo_tests/1", merging: true)
      ENV["TEST_ENV_NUMBER"] = "1"
      ENV["PARALLEL_TEST_GROUPS"] = groups
      config.merging merging
      config.coverage_dir dir
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(current)
    end

    it "keeps the inferred warning to one emission" do
      configure_parallel_worker(adapter)

      expect(capture_stderr { 2.times { config.finalize_merge } }.scan("SimpleCov inferred").size).to eq(1)
    end

    it "stays silent when print_errors is false" do
      configure_parallel_worker(adapter)
      config.print_errors false

      expect(capture_stderr { config.finalize_merge }).to be_empty
    end

    it "does not infer false without an active parallel adapter" do
      configure_parallel_worker(nil)

      expect(config.finalize_merge).to be true
    end

    it "does not infer false for a single-worker parallel run" do
      configure_parallel_worker(Class.new(SimpleCov::ParallelAdapters::Base), groups: "1")

      expect(config.finalize_merge).to be true
    end

    it "does not infer false when merging is disabled" do
      configure_parallel_worker(adapter, merging: false)

      expect(config.finalize_merge).to be true
    end

    it "does not infer false without an explicitly custom coverage destination" do
      ENV["TEST_ENV_NUMBER"] = "1"
      ENV["PARALLEL_TEST_GROUPS"] = "3"
      config.merging true
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

      expect(config.finalize_merge).to be true
    end

    it "infers false for a two-worker run, the smallest parallel one" do
      two_workers = Class.new(SimpleCov::ParallelAdapters::Base) do
        def self.expected_worker_count = 2
      end
      configure_parallel_worker(two_workers, groups: "2")

      expect(without_stderr { config.finalize_merge }).to be false
    end

    %w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS].each do |variable|
      it "recognises a worker environment from #{variable} alone" do
        ENV[variable] = "1"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        capture_stderr { expect(config.finalize_merge).to be false }
      end
    end

    it "does not infer false when the explicit destination is the default one" do
      configure_parallel_worker(adapter, dir: "coverage")

      expect(config.finalize_merge).to be true
    end

    it "colours the inference warning, so it is not lost in the run's output" do
      configure_parallel_worker(adapter)
      allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

      expect(capture_stderr { config.finalize_merge }).to start_with("\e[33m")
    end

    it "stays silent when it infers that this process should finalize" do
      config.merging true
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(nil)

      expect(capture_stderr { config.finalize_merge }).to be_empty
    end

    it "does not infer false outside a parallel worker environment" do
      config.merging true
      config.coverage_dir "coverage/turbo_tests/1"
      allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

      expect(config.finalize_merge).to be true
    end
  end

  describe "#use_merging (deprecated)" do
    around do |example|
      previous = config.instance_variable_get(:@use_merging)
      config.instance_variable_set(:@use_merging, nil)
      example.run
      config.instance_variable_set(:@use_merging, previous)
    end

    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.use_merging(false) })
        .to include("[DEPRECATION]").and include("`SimpleCov.use_merging`")
    end

    it "names `merging` as the replacement" do
      expect(capture_stderr { config.use_merging(false) }).to include("`SimpleCov.merging`")
    end

    it "still stores what it was given" do
      capture_stderr { config.use_merging(false) }

      expect(config.instance_variable_get(:@use_merging)).to be false
    end

    it "returns the stored value like `merging` does" do
      result = nil
      capture_stderr { result = config.use_merging(false) }

      expect(result).to be false
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

    it "replaces a stored value with a later one" do
      config.merge_subprocesses true
      config.merge_subprocesses false

      expect(config.merge_subprocesses).to be false
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
    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.enable_for_subprocesses(true) })
        .to include("[DEPRECATION]").and include("`SimpleCov.enable_for_subprocesses`")
    end

    it "names `merge_subprocesses` as the replacement" do
      expect(capture_stderr { config.enable_for_subprocesses(true) })
        .to include("`SimpleCov.merge_subprocesses`")
    end

    it "still stores what it was given" do
      capture_stderr { config.enable_for_subprocesses(true) }

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

      it "enables the regular criterion it was given alongside eval" do
        config.enable_coverage :branch, :eval

        expect(config.coverage_criteria).to include :branch
      end

      it "enables eval coverage in the same call" do
        config.enable_coverage :branch, :eval

        expect(config.coverage_for_eval_enabled?).to be true
      end
    end
  end

  describe "#cover_views" do
    context "when the runtime supports eval coverage" do
      before { allow(config).to receive(:coverage_for_eval_supported?).and_return(true) }

      it "defaults to a Rails app's views in every language it can compile" do
        expect(config.cover_views).to eq(["app/views/**/*.{erb,haml,slim}"])
      end

      it "takes globs of its own" do
        config.cover_views "app/views/**/*.erb", "app/components/**/*.erb"

        expect(config.view_globs).to eq(["app/views/**/*.erb", "app/components/**/*.erb"])
      end

      it "flattens and compacts what it is given" do
        config.cover_views ["app/views/**/*.erb", nil]

        expect(config.view_globs).to eq(["app/views/**/*.erb"])
      end

      it "enables eval coverage, which is what measures a rendered template" do
        config.cover_views

        expect(config.coverage_for_eval_enabled?).to be true
      end

      it "turns view coverage on" do
        config.cover_views

        expect(config.view_coverage?).to be true
      end

      it "hands out a fresh copy of the default, not the frozen constant" do
        config.cover_views << "app/components/**/*.erb"

        expect(SimpleCov::Configuration::DEFAULT_VIEW_GLOBS).to eq(["app/views/**/*.{erb,haml,slim}"])
      end
    end

    context "when the runtime has no eval coverage" do
      before { allow(config).to receive(:coverage_for_eval_supported?).and_return(false) }

      it "warns that it cannot measure them" do
        expect(capture_stderr { config.cover_views }).to include("Coverage for eval is not available")
      end

      it "leaves view coverage off" do
        capture_stderr { config.cover_views }

        expect(config.view_coverage?).to be false
      end
    end

    it "matches no template until asked for" do
      expect(config.view_globs).to be_nil
    end

    it "is off until asked for" do
      expect(config.view_coverage?).to be false
    end
  end

  describe "#maximum_missed and #maximum_missed_per_file" do
    %i[maximum_missed maximum_missed_per_file maximum_missed_per_file_overrides].each do |setting|
      it "defaults #{setting} to empty, which disables it" do
        expect(config.public_send(setting)).to eq({})
      end
    end

    it "targets the primary criterion with a bare suite-wide count" do
      config.maximum_missed 12

      expect(config.maximum_missed).to eq(line: 12)
    end

    it "targets it with a bare per-file count too" do
      capture_stderr { config.maximum_missed_per_file 5 }

      expect(config.maximum_missed_per_file).to eq(line: 5)
    end

    context "with the flat maximum_missed_per_file setter" do
      let(:warning) do
        config.enable_coverage :branch
        capture_stderr { config.maximum_missed_per_file line: 5, branch: 2 }
      end

      it "deprecates it with a copy-pastable replacement" do
        expect(warning).to include("[DEPRECATION]").and include("coverage(:line) { maximum_missed 5, per: :file }")
      end

      it "writes one out per criterion" do
        expect(warning).to include("coverage(:branch) { maximum_missed 2, per: :file }")
      end

      it "still stores what it was given" do
        warning

        expect(config.maximum_missed_per_file).to eq(line: 5, branch: 2)
      end
    end

    it "take criterion-keyed counts" do
      config.enable_coverage :branch
      config.maximum_missed line: 12, branch: 3

      expect(config.maximum_missed).to eq(line: 12, branch: 3)
    end

    it "reject a cap for a disabled criterion" do
      expect { config.maximum_missed branch: 3 }
        .to raise_error(SimpleCov::ConfigurationError, /branch/)
    end

    it "reject a negative count" do
      expect { config.maximum_missed(-1) }
        .to raise_error(SimpleCov::ConfigurationError, /maximum_missed takes a non-negative integer/)
    end

    it "reject a non-integer count" do
      expect { config.coverage(:line) { maximum_missed 2.5, per: :file } }
        .to raise_error(SimpleCov::ConfigurationError, /non-negative integer/)
    end
  end

  describe "the coverage block's maximum_missed verb" do
    after { config.clear_coverage_criteria }

    context "with caps for the block's criterion" do
      before do
        config.coverage :branch do
          maximum_missed 3
          maximum_missed 1, per: :file
        end
      end

      it "stores the suite-wide one" do
        expect(config.maximum_missed).to eq(branch: 3)
      end

      it "stores the per-file one" do
        expect(config.maximum_missed_per_file).to eq(branch: 1)
      end
    end

    context "with a per-path override target" do
      before do
        config.coverage :line do
          maximum_missed 5, per: :file
          maximum_missed 0, per: "lib/critical.rb"
        end
      end

      it "keeps the per-file default" do
        expect(config.maximum_missed_per_file).to eq(line: 5)
      end

      it "overrides it for the path" do
        expect(config.maximum_missed_per_file_overrides).to eq("lib/critical.rb" => {line: 0})
      end
    end

    it "works as a one-liner keyword" do
      config.coverage :method, maximum_missed: 2

      expect(config.maximum_missed).to eq(method: 2)
    end

    it "rejects a group target until group caps are enforced" do
      expect { config.coverage(:line) { maximum_missed 5, per: group("Models") } }
        .to raise_error(SimpleCov::ConfigurationError, /per: group/)
    end

    it "rejects a per: target it cannot read as a scope" do
      expect { config.coverage(:line) { maximum_missed 5, per: 42 } }
        .to raise_error(SimpleCov::ConfigurationError, /`per:` must be/)
    end

    it "rejects an only: target that is neither String nor Regexp (deprecated verb)" do
      capture_stderr do
        expect { config.coverage(:line) { maximum_missed_per_file 5, only: 42 } }
          .to raise_error(SimpleCov::ConfigurationError, /`only:`/)
      end
    end
  end

  describe "#history_limit and #drop_baseline" do
    it "defaults to 100 entries" do
      expect(config.history_limit).to eq(100)
    end

    it "answers the limit it was given" do
      expect(config.history_limit(10)).to eq(10)
    end

    it "measures against the last run by default" do
      expect(config.drop_baseline).to eq(:last_run)
    end

    [10, 0].each do |limit|
      it "takes #{limit} as the limit" do
        config.history_limit limit

        expect(config.history_limit).to eq(limit)
      end
    end

    [-1, 1.5].each do |limit|
      it "rejects #{limit.inspect} as a limit" do
        expect { config.history_limit(limit) }.to raise_error(SimpleCov::ConfigurationError, /non-negative/)
      end
    end

    %i[median branch].each do |baseline|
      it "takes the #{baseline} baseline" do
        config.drop_baseline baseline

        expect(config.drop_baseline).to eq(baseline)
      end
    end

    it "reject an unknown baseline" do
      expect { config.drop_baseline :mean }
        .to raise_error(SimpleCov::ConfigurationError, /:last_run, :median, :branch/)
    end
  end

  describe "#deprecations" do
    it "defaults to :warn" do
      expect(config.deprecations).to eq(:warn)
    end

    %i[raise warn].each do |mode|
      it "accepts :#{mode}" do
        config.deprecations mode

        expect(config.deprecations).to eq(mode)
      end
    end

    it "rejects any other mode" do
      expect { config.deprecations :silence }
        .to raise_error(SimpleCov::ConfigurationError, /:warn or :raise/)
    end
  end

  describe "#baseline_file and #baseline" do
    it "defaults to .simplecov_baseline.yml" do
      expect(config.baseline_file).to eq(".simplecov_baseline.yml")
    end

    it "takes a custom path" do
      config.baseline_file "config/coverage_floors.yml"
      expect(config.baseline_file).to eq("config/coverage_floors.yml")
    end

    it "answers the path it was given" do
      expect(config.baseline_file("config/coverage_floors.yml")).to eq("config/coverage_floors.yml")
    end

    it "returns nil when no baseline file exists under root" do
      Dir.mktmpdir do |dir|
        config.root(dir)
        expect(config.baseline).to be_nil
      end
    end

    it "reads the baseline file relative to root" do
      with_a_baseline_file do
        expect(config.baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: nil)
      end
    end

    it "reads it once per resolved path" do
      with_a_baseline_file { expect(config.baseline).to equal(config.baseline) }
    end

    def with_a_baseline_file
      Dir.mktmpdir do |dir|
        config.root(dir)
        File.write(File.join(dir, ".simplecov_baseline.yml"), "lib/foo.rb: 41.2\n")
        yield
      end
    end

    it "reads no baseline from a path nothing configured" do
      with_an_unconfigured_baseline_file { expect(config.baseline).to be_nil }
    end

    it "re-reads when the configured path changes" do
      with_an_unconfigured_baseline_file do
        config.baseline
        config.baseline_file "floors.yml"

        expect(config.baseline.covers?("lib/foo.rb", :line)).to be true
      end
    end

    def with_an_unconfigured_baseline_file
      Dir.mktmpdir do |dir|
        config.root(dir)
        File.write(File.join(dir, "floors.yml"), "lib/foo.rb: 41.2\n")
        yield
      end
    end
  end

  describe "#enable_coverage_for_eval (deprecated)" do
    before { allow(config).to receive(:coverage_for_eval_supported?).and_return(true) }

    it "names itself in the deprecation it warns with" do
      expect(capture_stderr { config.enable_coverage_for_eval })
        .to include("[DEPRECATION]").and include("`SimpleCov.enable_coverage_for_eval`")
    end

    it "names its replacement" do
      expect(capture_stderr { config.enable_coverage_for_eval })
        .to include("`SimpleCov.enable_coverage :eval`")
    end

    it "still toggles the flag" do
      capture_stderr { config.enable_coverage_for_eval }

      expect(config.coverage_for_eval_enabled?).to be true
    end
  end

  shared_examples "setting coverage expectations" do |coverage_setting|
    after do
      config.clear_coverage_criteria
    end

    it "expects nothing until it is told to" do
      expect(config.public_send(coverage_setting)).to eq({})
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

  describe "#minimum_coverage_by_file" do
    before { allow(SimpleCov::Deprecation).to receive(:warn) }
    after { config.clear_coverage_criteria }

    it_behaves_like "setting coverage expectations", :minimum_coverage_by_file

    it "warns with the equivalent `coverage` configuration built from the real arguments" do
      config.minimum_coverage_by_file :line => 70, "app/x.rb" => 100

      expect(SimpleCov::Deprecation).to have_received(:warn).with(a_string_including(
        "`SimpleCov.minimum_coverage_by_file` is deprecated",
        'coverage(:line) { minimum 70, per: :file; minimum 100, per: "app/x.rb" }'
      ))
    end

    context "with Symbol-keyed defaults beside String-keyed overrides" do
      before { config.minimum_coverage_by_file :line => 70, "app/critical.rb" => 100 }

      it "reads the Symbol keys as the default" do
        expect(config.minimum_coverage_by_file).to eq line: 70
      end

      it "reads the String keys as overrides" do
        expect(config.minimum_coverage_by_file_overrides).to eq("app/critical.rb" => {line: 100})
      end
    end

    context "with a Numeric override alone" do
      before { config.minimum_coverage_by_file "app/critical.rb" => 100 }

      it "sets no default" do
        expect(config.minimum_coverage_by_file).to eq({})
      end

      it "normalizes it into the primary criterion" do
        expect(config.minimum_coverage_by_file_overrides).to eq("app/critical.rb" => {line: 100})
      end
    end

    context "with per-path overrides" do
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

      it "warns about an override above 100% under the setting's own name" do
        allow(config).to receive(:warn)
        config.minimum_coverage_by_file "app/critical.rb" => 100.01

        expect(config).to have_received(:warn)
          .with("The coverage you set for minimum_coverage_by_file is greater than 100%")
      end

      it "preserves the declaration order of overrides" do
        config.minimum_coverage_by_file("lib/" => 80, "lib/critical.rb" => 100, %r{spec/} => 50)

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
    before do
      allow(config).to receive(:warn)
      allow(SimpleCov::Deprecation).to receive(:warn)
    end

    after do
      config.clear_coverage_criteria
    end

    it "expects nothing until it is told to" do
      expect(config.minimum_coverage_by_group).to eq({})
    end

    it "does not warn that coverage exceeds 100% for a valid value" do
      config.minimum_coverage_by_group({"Test Group 1" => 100.00})
      expect(config).not_to have_received(:warn).with(/is greater than 100%/)
    end

    it "warns you about your usage" do
      config.minimum_coverage_by_group({"Test Group 1" => 100.01})
      expect(config).to have_received(:warn)
        .with("The coverage you set for minimum_coverage_by_group is greater than 100%")
    end

    it "normalizes Symbol group names to Strings like `group` does" do
      config.minimum_coverage_by_group({Models: 80})
      expect(config.minimum_coverage_by_group).to eq("Models" => {line: 80})
    end

    it "warns with the equivalent `coverage` configuration built from the real arguments" do
      config.minimum_coverage_by_group({"Models" => 80})

      expect(SimpleCov::Deprecation).to have_received(:warn).with(a_string_including(
        "`SimpleCov.minimum_coverage_by_group` is deprecated",
        'coverage(:line) { minimum 80, per: group("Models") }'
      ))
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

    it "sets minimum_coverage when called with a number" do
      config.expected_coverage(95.42)

      expect(config.minimum_coverage).to eq line: 95.42
    end

    it "sets maximum_coverage to it too" do
      config.expected_coverage(95.42)

      expect(config.maximum_coverage).to eq line: 95.42
    end

    context "when called with a per-criterion hash" do
      before do
        config.enable_coverage :branch
        config.expected_coverage(line: 90.0, branch: 85.0)
      end

      it "sets the minimum" do
        expect(config.minimum_coverage).to eq line: 90.0, branch: 85.0
      end

      it "sets the maximum to it too" do
        expect(config.maximum_coverage).to eq line: 90.0, branch: 85.0
      end
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

    it "answers the minimum when it is not given one" do
      config.minimum_coverage 80

      expect(config.expected_coverage).to eq(line: 80)
    end

    it "pins the minimum when it is given an expectation" do
      config.expected_coverage 90

      expect(config.minimum_coverage).to eq(line: 90)
    end

    it "pins the maximum when it is given an expectation" do
      config.expected_coverage 90

      expect(config.maximum_coverage).to eq(line: 90)
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

    context "when oneshot line coverage is enabled over line" do
      before do
        config.primary_coverage :line
        config.enable_coverage :oneshot_line
      end

      it "replaces line" do
        expect(config.coverage_criteria).to contain_exactly(:oneshot_line)
      end

      it "resets the primary criterion to it" do
        expect(config.primary_coverage).to eq(:oneshot_line)
      end
    end

    context "when line coverage is enabled over oneshot" do
      before do
        config.enable_coverage :oneshot_line
        config.primary_coverage :oneshot_line
        config.enable_coverage :line
      end

      it "replaces oneshot line coverage" do
        expect(config.coverage_criteria).to contain_exactly(:line)
      end

      it "resets the primary criterion to it" do
        expect(config.primary_coverage).to eq(:line)
      end
    end

    it "lets the last variadic line mode win" do
      config.enable_coverage :branch, :method, :oneshot_line, :line

      expect(config.coverage_criteria).to contain_exactly(:branch, :method, :line)
    end

    it "lets a later call flip it again, without removing other criteria" do
      config.enable_coverage :branch, :method, :oneshot_line, :line
      config.enable_coverage :line, :oneshot_line

      expect(config.coverage_criteria).to contain_exactly(:branch, :method, :oneshot_line)
    end

    it "can't enable arbitrary things" do
      expect do
        config.enable_coverage :unknown
      end.to raise_error(/unsupported.*unknown.*line/i)
    end
  end

  describe "the coverage block's ignore verb" do
    after { config.clear_coverage_criteria }

    %i[ignored_branches ignored_methods].each do |setting|
      it "defaults #{setting} to empty" do
        expect(config.public_send(setting)).to eq []
      end
    end

    %i[implicit_else eval_generated].each do |token|
      it "stores :#{token} for coverage :branch" do
        config.coverage(:branch) { ignore :implicit_else, :eval_generated }

        expect(config.ignored_branch?(token)).to be true
      end
    end

    it "stores method tokens for coverage :method" do
      config.coverage(:method) { ignore :eval_generated }

      expect(config.ignored_methods).to eq [:eval_generated]
    end

    it "reads a stored one back" do
      config.coverage(:method) { ignore :eval_generated }

      expect(config.ignored_method?(:eval_generated)).to be true
    end

    it "unions and deduplicates across calls" do
      config.coverage(:branch) { ignore :implicit_else }
      config.coverage(:branch) { ignore :implicit_else }

      expect(config.ignored_branches).to eq [:implicit_else]
    end

    it "raises on an unknown branch token, naming the supported ones" do
      expect { config.coverage(:branch) { ignore :implict_else } }
        .to raise_error(SimpleCov::ConfigurationError,
          /branch type :implict_else.*Supported values are \[:implicit_else, :eval_generated\]/m)
    end

    it "raises on an unknown method token, naming the supported ones" do
      expect { config.coverage(:method) { ignore :nope } }
        .to raise_error(SimpleCov::ConfigurationError,
          /Unsupported method type :nope.*Supported values are \[:eval_generated\]/m)
    end

    it "rejects criteria without ignorable entry types" do
      expect { config.coverage(:line) { ignore :eval_generated } }
        .to raise_error(SimpleCov::ConfigurationError, /`ignore` is supported for `coverage :branch`/)
    end

    it "works as a one-liner keyword with a single token" do
      config.coverage :method, ignore: :eval_generated

      expect(config.ignored_method?(:eval_generated)).to be true
    end

    it "works as a one-liner keyword with an Array" do
      config.coverage :branch, ignore: %i[implicit_else eval_generated]

      expect(config.ignored_branches).to eq %i[implicit_else eval_generated]
    end
  end

  describe "#ignore_branches and #ignore_methods (deprecated)" do
    it "warns when ignore_branches is called" do
      expect(capture_stderr { config.ignore_branches :implicit_else, :eval_generated })
        .to include("[DEPRECATION]")
    end

    it "names the coverage-block replacement for ignore_branches" do
      expect(capture_stderr { config.ignore_branches :implicit_else, :eval_generated })
        .to include("`coverage(:branch) { ignore :implicit_else, :eval_generated }`")
    end

    it "still stores what ignore_branches was given" do
      capture_stderr { config.ignore_branches :implicit_else, :eval_generated }

      expect(config.ignored_branches).to eq %i[implicit_else eval_generated]
    end

    it "names the coverage-block replacement for ignore_methods" do
      expect(capture_stderr { config.ignore_methods :eval_generated })
        .to include("`coverage(:method) { ignore :eval_generated }`")
    end

    it "still stores what ignore_methods was given" do
      capture_stderr { config.ignore_methods :eval_generated }

      expect(config.ignored_methods).to eq [:eval_generated]
    end

    it "leaves the enabled criteria alone" do
      capture_stderr { config.ignore_branches :implicit_else }

      expect(config.coverage_criteria).to contain_exactly :line
    end

    it "stores the setting all the same" do
      capture_stderr { config.ignore_branches :implicit_else }

      expect(config.ignored_branch?(:implicit_else)).to be true
    end

    it "leaves a later enable_coverage to do its own work" do
      capture_stderr { config.ignore_branches :implicit_else }
      config.enable_coverage :branch

      expect(config.coverage_criteria).to include :branch
    end

    it "keeps the setting across it" do
      capture_stderr { config.ignore_branches :implicit_else }
      config.enable_coverage :branch

      expect(config.ignored_branch?(:implicit_else)).to be true
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

    it "leaves a primary criterion that is still enabled alone", if: SimpleCov.method_coverage_supported? do
      config.enable_coverage :branch, :method
      config.primary_coverage :method
      config.disable_coverage :line

      expect(config.primary_coverage).to eq :method
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

    it "returns false where the runtime cannot measure branches, even when asked to" do
      config.enable_coverage :branch
      allow(config).to receive(:branch_coverage_supported?).and_return(false)

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

    it "returns false where the runtime cannot measure methods, even when asked to" do
      config.enable_coverage :method
      allow(config).to receive(:method_coverage_supported?).and_return(false)

      expect(config).not_to be_method_coverage
    end
  end

  describe "#enable_coverage with :method" do
    it "can enable method coverage" do
      config.enable_coverage :method

      expect(config.coverage_criteria).to contain_exactly :line, :method
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

    it "answers the formatter it was given" do
      config.formatter(SimpleCov::Formatter::SimpleFormatter)

      expect(config.formatter).to eq(SimpleCov::Formatter::SimpleFormatter)
    end

    it "answers a formatter stored through the writer when called bare" do
      config.formatter = SimpleCov::Formatter::SimpleFormatter

      expect(config.formatter).to eq(SimpleCov::Formatter::SimpleFormatter)
    end

    it "treats false as an explicit opt-out (no raise)" do
      config.formatter(false)

      expect(config.formatter).to be_nil
    end

    it "leaves no formatter behind either way" do
      config.formatter(false)

      expect(config.formatters).to eq([])
    end

    it "treats nil as an explicit opt-out (no raise)" do
      config.formatter(nil)
      expect(config.formatter).to be_nil
    end
  end

  describe "#formats" do
    after do
      config.instance_variable_set(:@formatter, SimpleCov::Formatter::HTMLFormatter)
    end

    it "maps built-in format names to their formatter classes" do
      config.formats :json, :simple

      expect(config.formatter.new.formatters)
        .to eq([SimpleCov::Formatter::JSONFormatter, SimpleCov::Formatter::SimpleFormatter])
    end

    it "resolves every built-in name" do
      config.formats :html, :json, :simple, :baseline

      expect(config.formatter.new.formatters).to eq(
        [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter,
          SimpleCov::Formatter::SimpleFormatter, SimpleCov::Formatter::BaselineFormatter]
      )
    end

    it "passes classes and instances through beside the names" do
      custom = Class.new { def format(_) = "ok" }
      config.formats :json, custom

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::JSONFormatter, custom])
    end

    it "rejects an unknown name, listing the built-ins" do
      expect { config.formats :xml }
        .to raise_error(SimpleCov::ConfigurationError, /Unknown format :xml.*:html, :json, :simple, and :baseline/m)
    end

    it "reads back the configured formatters when called bare" do
      config.formatter = SimpleCov::Formatter::SimpleFormatter
      expect(config.formats).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "answers the formatters it configured" do
      expect(config.formats(:json, :simple)).to eq([config.formatter])
    end
  end

  describe "#formatters" do
    after do
      config.instance_variable_set(:@formatter, SimpleCov::Formatter::HTMLFormatter)
    end

    it "stores the formatters it is given" do
      config.formatter = SimpleCov::Formatter::HTMLFormatter
      config.formatters([SimpleCov::Formatter::SimpleFormatter])

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "answers what it was given" do
      config.formatter = SimpleCov::Formatter::HTMLFormatter

      expect(config.formatters([SimpleCov::Formatter::SimpleFormatter]))
        .to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "wraps a single formatter as an Array" do
      config.formatter = SimpleCov::Formatter::SimpleFormatter
      expect(config.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "accepts an empty Array as an explicit opt-out" do
      config.formatters([])

      expect(config.formatter).to be_nil
    end

    it "leaves an empty formatters list after the Array opt-out" do
      config.formatters([])

      expect(config.formatters).to eq([])
    end

    it "accepts a single formatter that is not wrapped in an Array" do
      config.formatters = SimpleCov::Formatter::SimpleFormatter
      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "accepts a MultiFormatter (a Class) and keeps its format chain working" do
      formatter = Class.new { def format(_) = "ok" }
      config.formatters = SimpleCov::Formatter::MultiFormatter.new([formatter])

      result = instance_double(SimpleCov::Result)
      expect(config.formatter.new.format(result).flatten).to eq(["ok"])
    end

    it "treats nil as an explicit opt-out" do
      config.formatters = nil

      expect(config.formatter).to be_nil
    end

    it "leaves an empty formatters list after the nil opt-out" do
      config.formatters = nil

      expect(config.formatters).to eq([])
    end

    it "treats false as an explicit opt-out, like `formatter false`" do
      config.formatters = false

      expect(config.formatter).to be_nil
    end

    it "leaves an empty formatters list after the false opt-out" do
      config.formatters = false

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

    context "when this process owns the final report" do
      let(:result) { instance_double(SimpleCov::Result) }

      before do
        allow(result).to receive(:format!)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: true)
        config.at_exit.call
      end

      it "reads the result" do
        expect(SimpleCov).to have_received(:result)
      end

      it "formats from the default proc" do
        expect(result).to have_received(:format!)
      end
    end

    it "still formats from the final process when parallel results are incomplete" do
      result = instance_double(SimpleCov::Result, format!: nil)
      allow(Coverage).to receive(:running?).and_return(true)
      allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: true,
        ready_to_process_results?: false)

      expect { config.at_exit.call }.to change { received_format?(result) }.to(true)
    end

    def received_format?(result)
      RSpec::Mocks.space.proxy_for(result).received_message?(:format!)
    end

    context "with a non-final parallel worker" do
      let(:result) { instance_double(SimpleCov::Result) }

      before do
        allow(result).to receive(:format!)
        allow(Coverage).to receive(:running?).and_return(true)
        allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: false)
        config.at_exit.call
      end

      it "stores the result" do
        expect(SimpleCov).to have_received(:result)
      end

      it "does not format from it" do
        expect(result).not_to have_received(:format!)
      end
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

    it "formats the result when this process owns the merge" do
      result = instance_double(SimpleCov::Result, format!: nil)
      allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: true, result?: true)

      config.at_exit.call

      expect(result).to have_received(:format!)
    end

    it "does nothing when another process owns the merge" do
      result = instance_double(SimpleCov::Result, format!: nil)
      allow(SimpleCov).to receive_messages(result: result, merge_finalization_owner?: false, result?: true)

      config.at_exit.call

      expect(result).not_to have_received(:format!)
    end

    it "does nothing when there is no result to format" do
      allow(SimpleCov).to receive_messages(result: nil, merge_finalization_owner?: true, result?: true)

      expect { config.at_exit.call }.not_to raise_error
    end

    it "answers a hook that answers nothing outside a session" do
      allow(SimpleCov).to receive_messages(result?: false, result: nil)
      allow(Coverage).to receive(:running?).and_return(false)

      expect(config.at_exit.call).to be_nil
    end

    it "answers the block it was given" do
      hook = proc { :mine }

      expect(config.at_exit(&hook)).to be(hook)
    end

    it "keeps it" do
      hook = proc { :mine }
      config.at_exit(&hook)

      expect(config.at_exit).to be(hook)
    end
  end

  describe "#at_fork" do
    it "remembers an explicit block across calls" do
      explicit = proc { |_pid| }
      config.at_fork(&explicit)

      expect(config.at_fork).to equal(explicit)
    end

    context "when the default lambda fires" do
      before do
        allow(SimpleCov).to receive_messages(command_name: "Suite", print_errors: nil, formatter: nil,
          minimum_coverage: nil, start: nil, subprocess_serial: 3)
        config.at_fork.call(12_345)
      end

      it "names the subprocess after the suite" do
        expect(SimpleCov).to have_received(:command_name).with("Suite (subprocess: 3)")
      end

      it "silences the child's errors" do
        expect(SimpleCov).to have_received(:print_errors).with(false)
      end

      it "gives the child a formatter that says nothing to the terminal" do
        expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
      end

      it "drops the child's threshold" do
        expect(SimpleCov).to have_received(:minimum_coverage).with(0)
      end

      it "starts it" do
        expect(SimpleCov).to have_received(:start)
      end
    end
  end

  describe "#subprocess_serial" do
    around do |example|
      previous = SimpleCov.current_run
      SimpleCov.current_run = SimpleCov::CurrentRun.new
      example.run
    ensure
      SimpleCov.current_run = previous
    end

    it "defaults to 0" do
      expect(SimpleCov.subprocess_serial).to eq(0)
    end

    it "increments monotonically" do
      2.times { SimpleCov.next_subprocess_serial! }

      expect(SimpleCov.subprocess_serial).to eq(2)
    end
  end

  describe "#command_name" do
    after { config.instance_variable_set(:@command_name, nil) }

    it "stores an explicit name" do
      config.command_name("My Suite")
      expect(config.command_name).to eq("My Suite")
    end

    it "guesses one from the running process when none was given" do
      allow(SimpleCov::CommandGuesser).to receive(:guess).and_return("Guessed")

      expect(config.command_name).to eq("Guessed")
    end
  end

  describe "#merge_timeout" do
    after { config.instance_variable_set(:@merge_timeout, nil) }

    it "stores an explicit integer value" do
      config.merge_timeout(120)
      expect(config.merge_timeout).to eq(120)
    end

    it "honors SIMPLECOV_MERGE_TIMEOUT over the configured value" do
      config.merge_timeout(120)
      stub_const("ENV", ENV.to_hash.merge("SIMPLECOV_MERGE_TIMEOUT" => "86400"))
      expect(config.merge_timeout).to eq(86_400)
    end

    it "ignores a malformed SIMPLECOV_MERGE_TIMEOUT" do
      stub_const("ENV", ENV.to_hash.merge("SIMPLECOV_MERGE_TIMEOUT" => "soon"))
      expect(config.merge_timeout).to eq(600)
    end

    it "keeps the timeout it worked out for later reads" do
      config.merge_timeout

      expect(config.instance_variable_get(:@merge_timeout)).to eq(600)
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

    it "builds a filter from a String argument" do
      expect(config.send(:parse_filter, "lib/legacy")).to be_a(SimpleCov::StringFilter)
    end

    it "builds a filter from a block" do
      expect(config.send(:parse_filter) { |sf| sf.filename.include?("legacy") }).to be_a(SimpleCov::BlockFilter)
    end
  end

  describe "#configure" do
    it "requires a configuration block" do
      expect { config.configure }.to raise_error(ArgumentError, /configuration block required/)
    end

    context "with a zero-parameter block" do
      let(:observed) { [] }
      let(:configured) do
        seen = observed
        config.configure do
          @configured = true
          seen.replace([self, binding.receiver, object_id, singleton_class])
        end
      end

      it "writes to the real configuration target" do
        configured

        expect(config.instance_variable_get(:@configured)).to be true
      end

      it "evaluates on it" do
        configured

        expect(observed).to eq([config, config, config.object_id, config.singleton_class])
      end

      it "answers it" do
        expect(configured).to be(config)
      end
    end

    context "with a parameterized block" do
      let(:owner) do
        Class.new do
          attr_reader :configured_self

          def initialize
            @threshold = 92
          end

          def apply_threshold(target)
            @configured_self = self
            target.minimum_coverage @threshold
          end
        end.new
      end
      let(:configured) do
        owner.instance_exec(config) { |target| target.configure { |dsl| apply_threshold(dsl) } }
      end

      it "passes the target explicitly" do
        configured

        expect(config.minimum_coverage).to eq(line: 92)
      end

      it "keeps the caller's context" do
        configured

        expect(owner.configured_self).to be(owner)
      end

      it "answers the target" do
        expect(configured).to be(config)
      end
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

    context "with a caller variable of the same name" do
      let(:owner) { Object.new }
      let(:observed) { [] }

      before do
        seen = observed
        owner.instance_variable_set(:@root, "/caller/project")
        config.root("/real/project")
        owner.instance_exec(config) do |target|
          target.configure { seen << @root } # rubocop:disable RSpec/InstanceVariable
        end
      end

      it "reads the configuration's own state" do
        expect(observed.first).to eq(File.expand_path("/real/project"))
      end

      it "leaves the caller's alone" do
        expect(owner.instance_variable_get(:@root)).to eq("/caller/project")
      end
    end

    it "derives cached configuration from the real configuration state" do
      owner = Object.new
      owner.instance_variable_set(:@root, "/wrong/project")
      config.root("/real/project")

      expect(configured_path(owner)).to eq(File.expand_path("/real/project/cov"))
    end

    def configured_path(owner)
      owner.instance_exec(config) do |target|
        target.configure do
          coverage_dir "cov"
          coverage_path
        end
        target.coverage_path
      end
    end

    context "with a block that reads its own scope" do
      let(:evaluated) do
        owner_class = Class.new do
          def evaluate(target)
            local = :present
            variables = nil
            outer_result = yield
            target.configure { variables = [binding.local_variables, block_given?, local, outer_result] }
            variables
          end
        end
        owner_class.new.evaluate(config) { :outer }
      end

      it "preserves the block's local variables" do
        expect(evaluated.first).to include(:local, :variables)
      end

      it "preserves block_given?" do
        expect(evaluated[1]).to be true
      end

      it "preserves the values those locals hold" do
        expect(evaluated[2]).to eq(:present)
      end

      it "preserves what the caller's own block answered" do
        expect(evaluated.last).to eq(:outer)
      end
    end

    it "resolves require_relative from the configuration source" do
      source_path = File.join(SimpleCov.root, "lib/simplecov.rb")
      configuration = eval(<<~RUBY, binding, source_path, 1) # rubocop:disable Style/EvalWithLocation
        proc { require_relative "simplecov/version" }
      RUBY

      expect { config.configure(&configuration) }.not_to raise_error
    end

    it "keeps the message the configuration block raised" do
      expect { config.configure(&raising_configuration) }.to raise_error("from config")
    end

    it "anchors configuration exceptions to their source" do
      expect(configuration_error.backtrace.first).to start_with("#{probe_path}:37:")
    end

    # Answers the error the raising configuration block leaves behind.
    def configuration_error
      config.configure(&raising_configuration)
      nil
    rescue RuntimeError => error
      error
    end

    def probe_path
      File.join(SimpleCov.root, "lib/configuration_probe.rb")
    end

    def raising_configuration
      eval(<<~RUBY, binding, probe_path, 37) # rubocop:disable Style/EvalWithLocation
        proc { raise "from config" }
      RUBY
    end

    context "with nested configuration blocks on the same target" do
      let(:observed) { [] }

      before do
        seen = observed
        config.configure do
          configure { @nested_state = :inner }
          seen << @nested_state # rubocop:disable RSpec/InstanceVariable
        end
      end

      it "composes them" do
        expect(observed.first).to eq(:inner)
      end

      it "leaves the state the inner block wrote" do
        expect(config.instance_variable_get(:@nested_state)).to eq(:inner)
      end
    end

    context "with nested configuration targets" do
      let(:other) { config_class.new }

      before do
        nested = other
        config.configure do
          @nested_state = :outer
          nested.configure { @nested_state = :inner }
        end
      end

      it "keeps the outer one's state" do
        expect(config.instance_variable_get(:@nested_state)).to eq(:outer)
      end

      it "keeps the inner one's state distinct" do
        expect(other.instance_variable_get(:@nested_state)).to eq(:inner)
      end
    end

    it "works from a frozen owner" do
      frozen_owner = Object.new.freeze

      expect(configured_from(frozen_owner)).to eq([frozen_owner, config])
    end

    it "works from an immediate-value owner" do
      expect(configured_from(1)).to eq([1, config])
    end

    def configured_from(owner)
      seen = []
      owner.instance_exec(config) { |target| target.configure { |dsl| seen.replace([self, dsl]) } }
      seen
    end

    it "does not leak configuration commands onto the caller during evaluation" do
      owner = Object.new
      release = configuring_in_another_thread(owner)

      expect { owner.command_name("outside-thread") }.to raise_error(NoMethodError)
    ensure
      release&.call
    end

    # Leaves a configure block parked mid-evaluation in another thread,
    # answering a lambda that releases it again.
    def configuring_in_another_thread(owner)
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
      -> {
        release << true if worker.alive?
        worker.join(2)
      }
    end

    it "preserves the block error even when the target freezes itself" do
      expect { config_class.new.configure(&freezing_configuration) }
        .to raise_error("original failure")
    end

    def freezing_configuration
      proc do
        @new_configuration_state = :set
        freeze
        raise "original failure"
      end
    end

    it "preserves normal unknown-command behavior" do
      expect { config.configure { unknown_configuration_command } }
        .to raise_error(NameError, /unknown_configuration_command/)
    end

    it "anchors an unknown command to the line that called it" do
      source_line = __LINE__ + 2

      error = capture_error(NameError) { config.configure { unknown_configuration_command } }

      expect(error.backtrace.first).to include("configuration_spec.rb:#{source_line}")
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

      it "leaves the flag false" do
        capture_stderr { config.enable_coverage_for_eval }

        expect(config.coverage_for_eval_enabled?).to be false
      end

      it "warns about the unsupported runtime" do
        expect(capture_stderr { config.enable_coverage_for_eval })
          .to include("Coverage for eval is not available")
      end
    end
  end

  describe "#primary_coverage" do
    context "when branch coverage is enabled" do
      before { config.enable_coverage :branch }

      it "enables branch coverage alongside line when branch becomes primary" do
        config.primary_coverage :branch

        expect(config.coverage_criteria).to contain_exactly :line, :branch
      end

      it "can set primary coverage to branch" do
        config.primary_coverage :branch

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

    it "enables nothing beyond line when line becomes primary" do
      config.primary_coverage :line

      expect(config.coverage_criteria).to contain_exactly :line
    end

    it "can set primary coverage to line" do
      config.primary_coverage :line

      expect(config.primary_coverage).to eq :line
    end

    it "keeps oneshot line coverage the only line criterion" do
      config.enable_coverage :oneshot_line
      config.primary_coverage :oneshot_line

      expect(config.coverage_criteria).to contain_exactly :oneshot_line
    end

    it "can set primary coverage to oneshot_line" do
      config.enable_coverage :oneshot_line
      config.primary_coverage :oneshot_line

      expect(config.primary_coverage).to eq :oneshot_line
    end

    it "can't set primary coverage to arbitrary things" do
      expect do
        config.primary_coverage :unknown
      end.to raise_error(/unsupported.*unknown.*line/i)
    end
  end

  describe "what the stores answer" do
    after { config.clear_coverage_criteria }

    it "answers the cover filters after adding one" do
      expect(config.cover("lib/**/*.rb")).to be(config.cover_filters)
    ensure
      config.cover_filters.clear
    end

    it "adds one filter for the glob" do
      config.cover("lib/**/*.rb")

      expect(config.cover_filters.size).to eq(1)
    ensure
      config.cover_filters.clear
    end

    it "answers the formatters after setting them" do
      expect(config.formatters(SimpleCov::Formatter::SimpleFormatter)).to be_a(Object)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "sets the one it was given" do
      config.formatters(SimpleCov::Formatter::SimpleFormatter)

      expect(config.formatters.size).to eq(1)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "answers the ignored method types after storing them" do
      stored = nil
      config.coverage(:method) { stored = ignore :eval_generated }

      expect(stored).to eq([:eval_generated])
    end

    it "answers the thresholds it normalised" do
      config.minimum_coverage 90

      expect(config.minimum_coverage).to eq(line: 90)
    end

    it "passes over a criterion with no threshold at all" do
      allow(SimpleCov::Deprecation).to receive(:warn)

      expect { config.coverage(:line) { minimum_per_file nil, only: "lib/a.rb" } }.not_to raise_error
    end
  end

  describe "how a deprecation reads" do
    after { config.clear_coverage_criteria }

    {
      "ignore_methods" => ->(config) { config.ignore_methods :eval_generated },
      "the block's maximum_missed_per_file" =>
        ->(config) { config.coverage(:line) { maximum_missed_per_file 5 } },
      "the block's minimum_per_group" =>
        ->(config) { config.coverage(:line) { minimum_per_group 90, only: "Models" } }
    }.each do |description, invocation|
      it "marks #{description} as deprecated" do
        stderr = capture_stderr { invocation.call(config) }

        expect(stderr).to include("[DEPRECATION]")
      end
    end

    it "renders one line per criterion, each on its own" do
      config.enable_coverage :branch
      stderr = capture_stderr { config.minimum_coverage_by_file line: 90, branch: 80 }

      expect(stderr).to include("  coverage(:line) { minimum 90, per: :file }\n  " \
                                "coverage(:branch) { minimum 80, per: :file }")
    end

    it "names the setting a deprecated per-file cap belongs to" do
      expect { capture_stderr { config.maximum_missed_per_file(-1) } }
        .to raise_error(SimpleCov::ConfigurationError,
          "maximum_missed_per_file takes a non-negative integer count of misses, got -1")
    end

    it "names the setting a deprecated per-file threshold belongs to" do
      stderr = capture_stderr { config.minimum_coverage_by_file 101 }

      expect(stderr).to include("The coverage you set for minimum_coverage_by_file is greater than 100%")
    end

    it "names the setting a per-path override belongs to" do
      stderr = capture_stderr { config.minimum_coverage_by_file("lib/a.rb" => 101) }

      expect(stderr).to include("The coverage you set for minimum_coverage_by_file is greater than 100%")
    end

    it "shows a key that is neither a criterion nor a path as it was written" do
      expect { capture_stderr { config.minimum_coverage_by_file(nil => 90) } }
        .to raise_error(SimpleCov::ConfigurationError,
          "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got nil")
    end
  end

  describe "per-file targets, everywhere they are taken" do
    after { config.clear_coverage_criteria }

    it "takes a Regexp subclass as a per-file threshold target" do
      pattern = Class.new(Regexp).new("lib/.*")
      config.coverage(:line) { minimum 90, per: pattern }

      expect(config.minimum_coverage_by_file_overrides.keys).to eq([pattern])
    end

    it "takes a Regexp subclass as a per-file threshold key" do
      allow(SimpleCov::Deprecation).to receive(:warn)
      pattern = Class.new(Regexp).new("lib/.*")
      config.minimum_coverage_by_file(pattern => 90)

      expect(config.minimum_coverage_by_file_overrides.keys).to eq([pattern])
    end

    it "shows a symbol where a cap's target belongs as it was written" do
      expect { capture_stderr { config.coverage(:line) { maximum_missed_per_file 5, only: :nope } } }
        .to raise_error(SimpleCov::ConfigurationError,
          "`only:` must be a String path or Regexp, got :nope")
    end

    it "takes a String subclass as a production coverage path" do
      path = Class.new(String).new("tmp/production.json")

      expect(config.production_coverage(path)).to eq(File.expand_path("tmp/production.json"))
    ensure
      config.remove_instance_variable(:@production_coverage) if config.instance_variable_defined?(:@production_coverage)
    end
  end

  describe "the small answers" do
    after { config.clear_coverage_criteria }

    it "answers a result already assembled as a session, whatever the result is" do
      allow(SimpleCov).to receive(:result?).and_return(instance_double(SimpleCov::Result))
      allow(Coverage).to receive(:running?).and_return(false)

      expect(config.send(:active_session?)).to be true
    end

    it "answers false, not nothing, about subprocesses nobody enabled" do
      expect(config.enabled_for_subprocesses?).to be false
    end

    it "answers the same baseline for a path it already read" do
      allow(SimpleCov::Baseline).to receive(:read_if_exists).and_return(SimpleCov::Baseline.new({}))
      first = config.baseline

      expect(config.baseline).to be(first)
    ensure
      forget_baseline
    end

    it "reads it once per resolved path" do
      allow(SimpleCov::Baseline).to receive(:read_if_exists).and_return(SimpleCov::Baseline.new({}))
      2.times { config.baseline }

      expect(SimpleCov::Baseline).to have_received(:read_if_exists).once
    ensure
      forget_baseline
    end

    def forget_baseline
      %i[@baseline @baseline_path].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end

    it "clears the leading criterion along with the criteria" do
      config.enable_coverage :branch
      config.primary_coverage :branch

      config.clear_coverage_criteria

      expect(config.primary_coverage).to eq(:line)
    end

    it "answers an empty chain, not nothing, when it clears the filters" do
      config.skip "vendor"

      expect(config.clear_filters).to eq([])
    end

    it "leaves an empty chain behind" do
      config.skip "vendor"
      config.clear_filters

      expect(config.filters).to eq([])
    end

    it "asks the runtime whether it can measure eval'd code, and believes the yes" do
      allow(Coverage).to receive(:supported?).with(:eval).and_return(true)

      expect(config.coverage_for_eval_supported?).to be true
    end

    it "answers that an ignored branch type is ignored" do
      config.coverage(:branch) { ignore :implicit_else }

      expect(config.ignored_branch?(:implicit_else)).to be true
    end

    it "answers that a branch type nobody ignored is not ignored" do
      config.coverage(:branch) { ignore :implicit_else }

      expect(config.ignored_branch?(:eval_generated)).to be false
    end

    it "answers the ignored types it stored" do
      stored = nil
      config.coverage(:branch) { stored = ignore :implicit_else }

      expect(stored).to eq([:implicit_else])
    end

    it "takes a merge timeout in seconds" do
      config.merge_timeout 120

      expect(config.merge_timeout).to eq(120)
    ensure
      forget_merge_timeout
    end

    it "ignores one that is not a count of seconds" do
      config.merge_timeout 120
      config.merge_timeout "600"

      expect(config.merge_timeout).to eq(120)
    ensure
      forget_merge_timeout
    end

    def forget_merge_timeout
      config.remove_instance_variable(:@merge_timeout) if config.instance_variable_defined?(:@merge_timeout)
    end

    [false, true].each do |finalizing|
      it "answers #{finalizing} for a final process configured to finalize #{finalizing}" do
        allow(config).to receive_messages(collating_result?: false, final_result_process?: true)
        config.finalize_merge finalizing

        expect(config.merge_finalization_owner?).to be finalizing
      ensure
        forget_finalize_merge
      end
    end

    def forget_finalize_merge
      %i[@finalize_merge @finalize_merge_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end
  end

  describe "naming a group" do
    after { config.groups.clear }

    it "takes a name and a block, with no filter argument at all" do
      config.group("Models") { |source_file| source_file.filename.include?("model") }

      expect(config.groups.keys).to eq(["Models"])
    end

    it "matches through the block it was given" do
      config.group("Models") { |source_file| source_file.filename.include?("model") }
      model = instance_double(SimpleCov::SourceFile, filename: "app/models/a.rb")

      expect(config.groups.fetch("Models").matches?(model)).to be true
    end

    it "refuses a name the report reserves" do
      expect { config.group("Ungrouped", "lib") }
        .to raise_error(SimpleCov::ConfigurationError, /Ungrouped/)
    end

    it "keeps each filter when the whole table is set at once" do
      config.groups = {"Models" => SimpleCov::StringFilter.new("models")}

      expect(config.groups.fetch("Models")
                   .matches?(instance_double(SimpleCov::SourceFile, project_filename: "app/models/a.rb"))).to be true
    end

    it "refuses a reserved name in a table set at once" do
      expect { config.groups = {"Ungrouped" => SimpleCov::StringFilter.new("models")} }
        .to raise_error(SimpleCov::ConfigurationError, /Ungrouped/)
    end
  end

  describe "what the setters answer" do
    after { config.clear_coverage_criteria }

    it "answers the formatters it has when asked for none" do
      expect(config.formats).to eq([])
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "answers the formatters it resolved" do
      expect(config.formats(:simple)).to eq(config.formatters)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "keeps the one it resolved" do
      config.formats(:simple)

      expect(config.formats.size).to eq(1)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "keeps it among the formatters too" do
      config.formats(:simple)

      expect(config.formatters.size).to eq(1)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    it "counts nothing until a destination is set outright" do
      expect(config.send(:explicit_coverage_destination?)).to be_falsey
    ensure
      forget_destination
    end

    it "counts a directory set outright" do
      config.coverage_dir "elsewhere"

      expect(config.send(:explicit_coverage_destination?)).to be_truthy
    ensure
      forget_destination
    end

    it "counts a path set outright, on its own" do
      config.coverage_path File.expand_path("tmp/elsewhere")

      expect(config.send(:explicit_coverage_destination?)).to be_truthy
    ensure
      forget_destination
    end
  end

  describe "the answers nothing else configures" do
    it "guesses a command name when nothing named the run" do
      forgotten = config_class.new

      expect(forgotten.command_name).to eq(SimpleCov::CommandGuesser.guess)
    end

    it "keeps the command name it was given" do
      config.command_name "Cucumber"

      expect(config.command_name).to eq("Cucumber")
    end

    it "reads a merge timeout out of the environment in base ten" do
      previous = ENV.fetch("SIMPLECOV_MERGE_TIMEOUT", nil)
      ENV["SIMPLECOV_MERGE_TIMEOUT"] = "010"

      expect(config.send(:env_merge_timeout)).to eq(10)
    ensure
      ENV["SIMPLECOV_MERGE_TIMEOUT"] = previous
    end

    it "reads no merge timeout out of an environment that carries none" do
      previous = ENV.fetch("SIMPLECOV_MERGE_TIMEOUT", nil)
      ENV.delete("SIMPLECOV_MERGE_TIMEOUT")

      expect(config.send(:env_merge_timeout)).to be_nil
    ensure
      ENV["SIMPLECOV_MERGE_TIMEOUT"] = previous
    end

    it "measures no view coverage with eval coverage but no globs" do
      allow(config).to receive(:coverage_for_eval_enabled?).and_return(true)

      expect(config.view_coverage?).to be false
    ensure
      config.instance_variable_set(:@view_globs, nil)
    end

    it "measures none with globs but no eval coverage" do
      config.cover_views "app/views/**/*.erb"
      allow(config).to receive(:coverage_for_eval_enabled?).and_return(false)

      expect(config.view_coverage?).to be false
    ensure
      config.instance_variable_set(:@view_globs, nil)
    end

    it "measures it with both" do
      config.cover_views "app/views/**/*.erb"
      allow(config).to receive(:coverage_for_eval_enabled?).and_return(true)

      expect(config.view_coverage?).to be true
    ensure
      config.instance_variable_set(:@view_globs, nil)
    end

    it "asks the runtime whether it can measure eval'd code" do
      allow(Coverage).to receive(:supported?).with(:eval).and_return(false)

      expect(config.coverage_for_eval_supported?).to be false
    end

    it "answers the cover filters after registering a block one" do
      registered = config.cover { |source_file| source_file.filename.end_with?("a.rb") }

      expect(registered).to be(config.cover_filters)
    ensure
      config.cover_filters.clear
    end

    it "registers one filter for the block" do
      config.cover { |source_file| source_file.filename.end_with?("a.rb") }

      expect(config.cover_filters.size).to eq(1)
    ensure
      config.cover_filters.clear
    end

    it "lets the block decide for itself" do
      config.cover { |source_file| source_file.filename.end_with?("a.rb") }
      file = instance_double(SimpleCov::SourceFile, filename: "lib/a.rb")

      expect(config.cover_filters.first.matches?(file)).to be true
    ensure
      config.cover_filters.clear
    end
  end

  describe "group thresholds, read and written" do
    after { config.clear_coverage_criteria }

    it "answers an empty table before anything sets one" do
      expect(config.minimum_coverage_by_group).to eq({})
    end

    it "answers what a group threshold was set to, from either spelling" do
      capture_stderr { config.minimum_coverage_by_group("Models" => 90) }
      config.coverage(:line) { minimum 80, per: group("Views") }

      expect(config.minimum_coverage_by_group).to eq("Models" => {line: 90}, "Views" => {line: 80})
    end

    it "warns about an impossible threshold, naming the group setting" do
      stderr = capture_stderr { config.minimum_coverage_by_group("Models" => 101) }

      expect(stderr).to include("The coverage you set for minimum_coverage_by_group is greater than 100%")
    end

    it "refuses a group threshold for a criterion nothing measures" do
      allow(SimpleCov::Deprecation).to receive(:warn)

      expect { config.minimum_coverage_by_group("Models" => {branch: 90}) }
        .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
    end

    it "warns about an impossible group threshold set through the block" do
      stderr = capture_stderr { config.coverage(:line) { minimum 101, per: group("Models") } }

      expect(stderr).to include("The coverage you set for minimum_coverage_by_group is greater than 100%")
    end

    it "refuses a group threshold for a criterion nothing measures, from the block" do
      expect { config.coverage(:branch, enabled: false) { minimum 90, per: group("Models") } }
        .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
    end

    it "renders the block form as the replacement for the flat setter" do
      stderr = capture_stderr { config.minimum_coverage_by_group("Models" => 90) }

      expect(stderr).to include(%(  coverage(:line) { minimum 90, per: group("Models") }))
    end

    it "renders a criterion-keyed group threshold as its own line" do
      config.enable_coverage :branch
      stderr = capture_stderr { config.minimum_coverage_by_group("Models" => {branch: 80}) }

      expect(stderr).to include(%(  coverage(:branch) { minimum 80, per: group("Models") }))
    end
  end

  describe "which criterion leads" do
    after { config.clear_coverage_criteria }

    it "keeps the criterion that was enabled first first" do
      config.disable_coverage :line
      config.enable_coverage :branch
      config.enable_coverage :line

      expect(config.coverage_criteria.first).to eq(:branch)
    end

    it "prefers line coverage all the same" do
      config.disable_coverage :line
      config.enable_coverage :branch
      config.enable_coverage :line

      expect(config.primary_coverage).to eq(:line)
    end
  end

  describe "ignoring synthetic entries" do
    after { config.clear_coverage_criteria }

    it "answers the types it ignores, however they are spelled" do
      expect(ignored_twice).to eq([:eval_generated])
    end

    it "keeps one entry per type" do
      ignored_twice

      expect(config.ignored_methods).to eq([:eval_generated])
    end

    def ignored_twice
      ignored = []
      config.coverage(:method) { ignore :eval_generated }
      config.coverage(:method) { ignored.replace(ignore([:eval_generated])) }
      ignored
    end

    it "refuses to ignore anything for a criterion that has nothing to ignore" do
      expect { config.coverage(:line) { ignore :eval_generated } }
        .to raise_error(SimpleCov::ConfigurationError,
          "`ignore` is supported for `coverage :branch` and `coverage :method`, not :line")
    end
  end

  describe "what a deprecation offers instead" do
    after { config.clear_coverage_criteria }

    it "renders one coverage block per criterion, a line each" do
      config.enable_coverage :branch
      stderr = capture_stderr { config.maximum_missed_per_file line: 5, branch: 2 }

      expect(stderr).to include("  coverage(:line) { maximum_missed 5, per: :file }\n  " \
                                "coverage(:branch) { maximum_missed 2, per: :file }")
    end

    it "renders a bare count against the leading criterion" do
      stderr = capture_stderr { config.maximum_missed_per_file 5 }

      expect(stderr).to include("  coverage(:line) { maximum_missed 5, per: :file }")
    end
  end

  describe "what the configuration works out for itself" do
    after { config.clear_coverage_criteria }

    it "leads with line coverage while it is measured" do
      expect(config.primary_coverage).to eq(:line)
    end

    it "leads with what is left when it is not" do
      config.enable_coverage :branch
      config.disable_coverage :line

      expect(config.primary_coverage).to eq(:branch)
    end

    it "has something to do at exit when a result is already assembled" do
      allow(SimpleCov).to receive(:result?).and_return(true)
      allow(Coverage).to receive(:running?).and_return(false)

      expect(config.send(:active_session?)).to be true
    end

    it "has nothing to do at exit with no result and no measurement" do
      allow(SimpleCov).to receive(:result?).and_return(false)
      allow(Coverage).to receive(:running?).and_return(false)

      expect(config.send(:active_session?)).to be false
    end

    it "has something to do at exit while measurement is running" do
      allow(SimpleCov).to receive(:result?).and_return(false)
      allow(Coverage).to receive(:running?).and_return(true)

      expect(config.send(:active_session?)).to be true
    end

    it "has nothing to do at exit when there is no Coverage to ask" do
      allow(SimpleCov).to receive(:result?).and_return(false)
      hide_const("Coverage")

      expect(config.send(:active_session?)).to be false
    end

    it "counts no destination at all as the default one" do
      expect(config.send(:explicit_custom_coverage_destination?)).to be false
    ensure
      forget_destination
    end

    it "counts the default directory set outright as the default one" do
      config.root "tmp/destination"
      config.coverage_dir "coverage"

      expect(config.send(:explicit_custom_coverage_destination?)).to be false
    ensure
      forget_destination
    end

    it "tells another directory from it" do
      config.root "tmp/destination"
      config.coverage_dir "elsewhere"

      expect(config.send(:explicit_custom_coverage_destination?)).to be true
    ensure
      forget_destination
    end

    it "counts a directory it was never told outright as the default one" do
      configure_forgotten_custom_dir

      expect(config.send(:explicit_custom_coverage_destination?)).to be false
    ensure
      forget_destination
    end

    # Leaves a custom coverage directory in place with no record of it having
    # been asked for outright.
    def configure_forgotten_custom_dir
      config.root "tmp/destination"
      config.coverage_dir "elsewhere"
      config.remove_instance_variable(:@coverage_dir_explicit)
    end

    it "does not call a directory explicit for having been read" do
      config.coverage_dir

      expect(config.send(:explicit_coverage_destination?)).to be_falsey
    ensure
      forget_destination
    end

    it "removes the filter it recognises from a chain holding a foreign object" do
      config.filters << Object.new
      config.skip "vendor"

      expect(config.remove_filter("vendor")).to be true
    ensure
      config.clear_filters
    end

    it "answers false for one it already removed" do
      remove_vendor_from_a_foreign_chain

      expect(config.remove_filter("vendor")).to be false
    ensure
      config.clear_filters
    end

    it "leaves the foreign object alone" do
      remove_vendor_from_a_foreign_chain

      expect(config.filters.size).to eq(1)
    ensure
      config.clear_filters
    end

    # Removes the vendor filter from a chain that also holds an object the
    # filter list knows nothing about.
    def remove_vendor_from_a_foreign_chain
      config.filters << Object.new
      config.skip "vendor"
      config.remove_filter("vendor")
    end
  end

  describe "where the report is written" do
    around do |example|
      previous = %i[@root @coverage_dir @coverage_path @coverage_dir_explicit @coverage_path_explicit]
        .filter_map do |ivar|
        if config.instance_variable_defined?(ivar)
          [ivar,
            config.instance_variable_get(ivar)]
        end
      end
      example.run
    ensure
      %i[@root @coverage_dir @coverage_path @coverage_dir_explicit @coverage_path_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
      previous.each { |ivar, value| config.instance_variable_set(ivar, value) }
    end

    def forget(*ivars)
      ivars.each { |ivar| config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar) }
    end

    it "answers the working directory before anything sets a root" do
      forget(:@root)

      expect(config.root).to eq(File.expand_path(Dir.getwd))
    end

    it "answers the default directory before anything sets one" do
      forget(:@coverage_dir)

      expect(config.coverage_dir).to eq("coverage")
    end

    it "writes a directory it is handed over one it already answered" do
      config.coverage_dir "first"

      expect(config.coverage_dir("second")).to eq("second")
    end

    it "resolves a root it is given against the working directory" do
      config.root "tmp/somewhere"

      expect(config.root).to eq(File.expand_path("tmp/somewhere"))
    end

    it "keeps answering it when handed nothing" do
      config.root "tmp/somewhere"

      expect(config.root(nil)).to eq(File.expand_path("tmp/somewhere"))
    end

    it "drops a coverage path computed from the old root" do
      first, second = coverage_paths_across_roots

      expect(second).not_to eq(first)
    end

    it "computes the coverage path from the root it was given last" do
      expect(coverage_paths_across_roots.last)
        .to eq(File.join(File.expand_path("tmp/second"), "coverage"))
    end

    # Answers the coverage path from one root and then the one from the next.
    def coverage_paths_across_roots
      config.root "tmp/first"
      first = config.coverage_path
      config.root "tmp/second"
      [first, config.coverage_path]
    ensure
      FileUtils.rm_rf([File.expand_path("tmp/first"), File.expand_path("tmp/second")])
    end

    it "drops a coverage path computed from the old directory" do
      config.root "tmp/first"
      config.coverage_dir "cov"

      expect(config.coverage_path).to eq(File.join(File.expand_path("tmp/first"), "cov"))
    ensure
      FileUtils.rm_rf(File.expand_path("tmp/first"))
    end

    it "keeps a coverage path that was set outright" do
      expect(coverage_path_pinned_across_roots).to eq(File.expand_path("tmp/explicit"))
    end

    # Answers the coverage path an example set outright, after the root moves
    # out from under it.
    def coverage_path_pinned_across_roots
      config.root "tmp/first"
      config.coverage_path File.expand_path("tmp/explicit")
      config.root "tmp/second"
      config.coverage_path
    ensure
      FileUtils.rm_rf([File.expand_path("tmp/first"), File.expand_path("tmp/second"),
        File.expand_path("tmp/explicit")])
    end
  end

  describe "reading and writing the formatter" do
    after { config.instance_variable_set(:@formatter, nil) }

    it "answers no formatters before one is set" do
      expect(config.formatters).to eq([])
    end

    it "wraps the formatter it is given in one that runs the whole list" do
      config.formatters SimpleCov::Formatter::SimpleFormatter

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "answers the one formatter it was given" do
      config.formatters SimpleCov::Formatter::SimpleFormatter

      expect(config.formatters.size).to eq(1)
    end

    it "answers what it was handed, so a chained call sees it" do
      formatters = [SimpleCov::Formatter::SimpleFormatter]

      expect(config.formatters(formatters)).to be(formatters)
    end

    it "opts out of formatting when handed an empty list" do
      config.formatters SimpleCov::Formatter::SimpleFormatter
      config.formatters = []

      expect(config.formatter).to be_nil
    end

    it "empties the formatters it was holding when handed an empty list" do
      config.formatters SimpleCov::Formatter::SimpleFormatter
      config.formatters = []

      expect(config.formatters).to eq([])
    end

    it "keeps the formatter it is handed" do
      config.formatter SimpleCov::Formatter::SimpleFormatter

      expect(config.formatter).to be(SimpleCov::Formatter::SimpleFormatter)
    end

    it "normalises false to no formatter at all" do
      config.formatter SimpleCov::Formatter::SimpleFormatter
      config.formatter false

      expect(config.formatter).to be_nil
    end

    it "resolves a built-in format name to its formatter" do
      config.formats :simple

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
    end

    it "answers the formatters it resolved when asked for the formats" do
      config.formats :simple

      expect(config.formats).to eq(config.formatters)
    end

    it "refuses a format name it does not know" do
      expect { config.formats :yaml }
        .to raise_error(SimpleCov::ConfigurationError, /Unknown format :yaml/)
    end

    it "leaves a formatter that is not a name alone" do
      formatter = SimpleCov::Formatter::SimpleFormatter.new

      expect(config.send(:resolve_format, formatter)).to be(formatter)
    end

    it "answers the HTML formatter for :html, having required it" do
      expect(config.send(:resolve_format, :html)).to eq(SimpleCov::Formatter::HTMLFormatter)
    end

    it "loads the HTML formatter for that name and no other" do
      allow(config).to receive(:require_html_formatter)

      config.send(:resolve_format, :html)
      config.send(:resolve_format, :simple)

      expect(config).to have_received(:require_html_formatter).with(:html).once
    end
  end

  describe "what the configuration answers about itself" do
    after do
      config.clear_coverage_criteria
      config.clear_filters
    end

    it "keeps the primary criterion when a different one is disabled" do
      config.enable_coverage :branch
      config.enable_coverage :method
      config.primary_coverage :branch
      config.disable_coverage :method

      expect(config.primary_coverage).to eq(:branch)
    end

    it "answers no branch coverage on a runtime that cannot measure it" do
      config.enable_coverage :branch
      allow(Coverage).to receive(:supported?).and_return(false)

      expect(config.branch_coverage?).to be false
    end

    it "answers no method coverage on a runtime that cannot measure it" do
      config.enable_coverage :method
      allow(Coverage).to receive(:supported?).and_return(false)

      expect(config.method_coverage?).to be false
    end

    it "answers that an ignored method type is ignored" do
      config.coverage(:method) { ignore :eval_generated }

      expect(config.ignored_method?(:eval_generated)).to be true
    end

    it "answers that a method type nobody ignored is not ignored" do
      config.coverage(:method) { ignore :eval_generated }

      expect(config.ignored_method?(:accessor)).to be false
    end

    it "removes the filter it recognises from a chain holding an argumentless one" do
      config.filters << SimpleCov::BlockFilter.new(->(source_file) { source_file.lines.count < 5 })
      config.skip "vendor"

      expect(config.remove_filter("vendor")).to be true
    end

    it "keeps a filter that has no argument to compare" do
      config.filters << SimpleCov::BlockFilter.new(->(source_file) { source_file.lines.count < 5 })
      config.skip "vendor"
      config.remove_filter("vendor")

      expect(config.filters.size).to eq(1)
    end

    it "answers a profiles registry, not the registry class" do
      expect(config.profiles).to be_a(SimpleCov::Profiles)
    end

    context "when the fork hook fires" do
      before do
        allow(SimpleCov).to receive(:command_name).and_return("Parent Suite")
        allow(SimpleCov).to receive(:print_errors)
        allow(SimpleCov).to receive(:formatter)
        allow(SimpleCov).to receive(:minimum_coverage)
        allow(SimpleCov).to receive(:start)

        config.at_fork.call(123)
      end

      it "renames the command for the subprocess" do
        expect(SimpleCov).to have_received(:command_name).with(/\AParent Suite \(subprocess: \d+\)\z/)
      end

      it "hands the subprocess the simple formatter" do
        expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
      end

      it "keeps the subprocess from printing errors" do
        expect(SimpleCov).to have_received(:print_errors).with(false)
      end

      it "drops the minimum coverage the subprocess has to reach" do
        expect(SimpleCov).to have_received(:minimum_coverage).with(0)
      end

      it "starts collecting again in the subprocess" do
        expect(SimpleCov).to have_received(:start)
      end
    end
  end

  describe "what a refusal shows of the value" do
    {
      "a string where a count belongs" =>
        [->(config) { config.coverage(:line) { maximum_missed "5" } },
          %(maximum_missed takes a non-negative integer count of misses, got "5")],
      "a symbol where a path belongs" =>
        [->(config) { config.coverage(:line) { minimum 90, per: :nope } },
          %(`per:` must be :file, a String path, a Regexp, or group("Name"), got :nope)],
      "a symbol where a per-file target belongs" =>
        [->(config) { config.coverage(:line) { minimum_per_file 90, only: :nope } },
          %(`only:` must be a String path or Regexp, got :nope)],
      "a string where a history limit belongs" =>
        [->(config) { config.history_limit("10") },
          %(history_limit takes a non-negative integer, got "10")]
    }.each do |description, (invocation, message)|
      it "shows #{description} as it was written" do
        expect { capture_stderr { invocation.call(config) } }
          .to raise_error(SimpleCov::ConfigurationError, message)
      end
    end

    it "names the block's own setting when its count is refused" do
      expect { config.coverage(:line) { maximum_missed(-1) } }
        .to raise_error(SimpleCov::ConfigurationError,
          "maximum_missed takes a non-negative integer count of misses, got -1")
    end

    it "refuses a cap for a criterion the run does not measure" do
      expect { config.coverage(:branch, enabled: false) { maximum_missed 3 } }
        .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
    end
  end

  describe "what a refusal says" do
    {
      "a negative suite-wide cap" =>
        [->(config) { config.maximum_missed(-1) },
          "maximum_missed takes a non-negative integer count of misses, got -1"],
      "a fractional per-file cap" =>
        [->(config) { config.coverage(:line) { maximum_missed 2.5, per: :file } },
          "maximum_missed_per_file takes a non-negative integer count of misses, got 2.5"],
      "a per: target that is neither a path nor a pattern" =>
        [->(config) { config.coverage(:line) { maximum_missed 5, per: 42 } },
          %(`per:` must be :file, a String path, a Regexp, or group("Name"), got 42)],
      "a negative history limit" =>
        [->(config) { config.history_limit(-1) },
          "history_limit takes a non-negative integer, got -1"],
      "an unknown drop baseline" =>
        [->(config) { config.drop_baseline :mean },
          "drop_baseline takes one of [:last_run, :median, :branch], got :mean"],
      "an unknown deprecation mode" =>
        [->(config) { config.deprecations :silence },
          "deprecations takes :warn or :raise, got :silence"],
      "a per-file threshold key of the wrong kind" =>
        [->(config) { config.minimum_coverage_by_file(42 => 90) },
          "minimum_coverage_by_file keys must be Symbol (criterion), String, or Regexp; got 42"],
      "an unsupported criterion" =>
        [->(config) { config.enable_coverage :sentence },
          "Unsupported coverage criterion sentence, supported values are [:line, :branch, :method, :oneshot_line]"]
    }.each do |description, (invocation, message)|
      it "names the setting and the value for #{description}" do
        expect { capture_stderr { invocation.call(config) } }
          .to raise_error(SimpleCov::ConfigurationError, message)
      end
    end

    it "names the value a deprecated per-file cap refused" do
      expect { capture_stderr { config.coverage(:line) { maximum_missed_per_file 5, only: 42 } } }
        .to raise_error(SimpleCov::ConfigurationError,
          "`only:` must be a String path or Regexp, got 42")
    end

    it "names the setting a threshold above 100% belongs to" do
      stderr = capture_stderr { config.coverage(:line) { maximum 101 } }

      expect(stderr).to include("The coverage you set for maximum_coverage is greater than 100%")
    end
  end

  describe "what counts as a path or a pattern" do
    let(:string_subclass) { Class.new(String) }
    let(:regexp_subclass) { Class.new(Regexp) }

    it "takes a String subclass as a per-file target" do
      target = string_subclass.new("lib/a.rb")
      config.coverage(:line) { minimum 90, per: target }

      expect(config.minimum_coverage_by_file_overrides.keys.map(&:to_s)).to eq(["lib/a.rb"])
    end

    it "takes a String subclass as a per-file cap target" do
      target = Class.new(String).new("lib/a.rb")
      config.coverage(:line) { maximum_missed 3, per: target }

      expect(config.maximum_missed_per_file_overrides.keys.map(&:to_s)).to eq(["lib/a.rb"])
    end

    it "takes a Regexp subclass as a per-file cap target" do
      pattern = regexp_subclass.new("lib/.*")
      config.coverage(:line) { maximum_missed 3, per: pattern }

      expect(config.maximum_missed_per_file_overrides.keys).to eq([pattern])
    end

    it "takes a String subclass as a per-file threshold key" do
      allow(SimpleCov::Deprecation).to receive(:warn)
      config.minimum_coverage_by_file(string_subclass.new("lib/a.rb") => 90)

      expect(config.minimum_coverage_by_file_overrides.keys.map(&:to_s)).to eq(["lib/a.rb"])
    end

    it "takes a Numeric that is not a Float as a group threshold" do
      allow(SimpleCov::Deprecation).to receive(:warn)
      config.minimum_coverage_by_group("Models" => Rational(90, 1))

      expect(config.minimum_coverage_by_group).to eq("Models" => {line: Rational(90, 1)})
    end
  end

  describe "#track_tests" do
    after { config.clear_coverage_criteria }

    it "is off by default" do
      expect(config.track_tests?).to be false
    end

    it "enables with a bare call" do
      config.track_tests

      expect(config.track_tests?).to be true
    end

    it "turns back off with an explicit false" do
      config.track_tests
      config.track_tests false

      expect(config.track_tests?).to be false
    end

    it "turns back on with an explicit true" do
      config.track_tests false
      config.track_tests true

      expect(config.track_tests?).to be true
    end

    it "keeps the granularity it was given when called again without one" do
      config.track_tests granularity: :file
      config.track_tests

      expect(config.track_tests_granularity).to eq(:file)
    end

    it "stays on when called again without a granularity" do
      config.track_tests granularity: :file
      config.track_tests

      expect(config.track_tests?).to be true
    end

    describe "granularity" do
      it "defaults to per-test attribution" do
        expect(config.track_tests_granularity).to eq(:test)
      end

      it "accepts :file for one context per test file" do
        config.track_tests granularity: :file

        expect(config.track_tests_granularity).to eq(:file)
      end

      it "turns tracking on when it is given a granularity" do
        config.track_tests granularity: :file

        expect(config.track_tests?).to be true
      end

      it "rejects anything else" do
        expect { config.track_tests granularity: :suite }
          .to raise_error(SimpleCov::ConfigurationError, /granularity/)
      end
    end

    describe "#validate_test_tracking!" do
      it "passes while tracking is off, whatever the criteria" do
        config.enable_coverage :oneshot_line

        expect { config.validate_test_tracking! }.not_to raise_error
      end

      it "passes with ordinary line coverage enabled" do
        config.track_tests

        expect { config.validate_test_tracking! }.not_to raise_error
      end

      it "rejects tracking under oneshot line coverage" do
        config.track_tests
        config.enable_coverage :oneshot_line

        expect { config.validate_test_tracking! }
          .to raise_error(SimpleCov::ConfigurationError, /track_tests.*line coverage/)
      end
    end
  end
end
