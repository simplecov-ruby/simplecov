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

  describe "explicit writers" do
    # Item 2 of the mutation-testing roadmap, in its non-breaking form:
    # every dual-purpose setting can also be written the way Ruby spells
    # writing. Each writer is the dual method's write arm, and the dual
    # method delegates to it, so the write behaviour lives once.

    it "writes root expanded, and re-derives the coverage path from it" do
      config.root = "tmp/project"

      expect(config.root).to eq(File.expand_path("tmp/project"))
      expect(config.coverage_path).to eq(File.expand_path("coverage", config.root))
    end

    it "resets root to the working directory when written nil" do
      config.root = nil

      expect(config.root).to eq(File.expand_path(Dir.getwd))
    end

    it "writes the coverage directory and re-derives the path" do
      config.root = "tmp/project"
      config.coverage_dir = "cov"

      expect(config.coverage_dir).to eq("cov")
      expect(config.coverage_path).to eq(File.expand_path("cov", config.root))
    end

    it "writes an explicit coverage path, expanded and created" do
      Dir.mktmpdir do |tmp|
        config.coverage_path = File.join(tmp, "out")

        expect(config.coverage_path).to eq(File.join(tmp, "out"))
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

    # The dual methods answer their write arms with the stored value,
    # the way they always did, even though the storing now happens in
    # the writer.
    it "answers the stored value when writing through the dual methods" do
      expect(config.baseline_file("config/floors.yml")).to eq("config/floors.yml")
      expect(config.history_limit(5)).to eq(5)
      expect(config.production_coverage("tmp/production.json"))
        .to eq(File.expand_path("tmp/production.json", config.root))
    end

    it "refuses a production_coverage that is not a path" do
      expect { config.production_coverage = 42 }.to raise_error(SimpleCov::ConfigurationError, /path/)
    end
  end

  describe "#load_coverage" do
    it "requires the stdlib Coverage library and answers what require answers" do
      allow(config).to receive(:require).and_return(false)

      expect(config.send(:load_coverage)).to be(false)
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

  # The criterion-first `coverage` method is a uniform front-end over the same
  # threshold stores the flat `minimum_coverage` family writes, so these
  # examples assert against those stores.
  describe "#coverage" do
    after { config.clear_coverage_criteria }

    # The criterion comes back, which is what a configuration file
    # chains from and what the oneshot variant answers with.
    it "answers the criterion it configured" do
      expect(config.coverage(:branch)).to eq(:branch)
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

    describe "per-file thresholds (per: :file and path targets)" do
      it "sets a default applied to every file" do
        config.coverage(:line) { minimum 80, per: :file }
        expect(config.minimum_coverage_by_file).to eq(line: 80)
      end

      it "overrides the default for a String path or Regexp target" do
        config.coverage :line do
          minimum 80,  per: :file
          minimum 100, per: "app/mailers/request_mailer.rb"
          minimum 95,  per: %r{\Aapp/payments/}
        end
        expect(config.minimum_coverage_by_file).to eq(line: 80)
        expect(config.minimum_coverage_by_file_overrides).to eq(
          "app/mailers/request_mailer.rb" => {line: 100},
          %r{\Aapp/payments/} => {line: 95}
        )
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

    describe "per-group thresholds (per: group targets)" do
      it "stores a per-criterion minimum under the named group" do
        config.coverage(:line) { minimum 95, per: group("Models") }
        config.coverage(:branch) { minimum 90, per: group("Models") }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95, branch: 90})
      end

      # `group :Models` normalizes to the String "Models", so the threshold
      # store must too. A Symbol key here missed the check-time lookup and
      # silently left the minimum unenforced.
      it "normalizes a Symbol group name to match Symbol-defined groups" do
        config.coverage(:line) { minimum 95, per: group(:Models) }
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95})
      end
    end

    describe "the deprecated suffixed scope verbs" do
      it "minimum_per_file warns with the per: replacement and still stores" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_file 80 } }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`minimum 80, per: :file`")
        expect(config.minimum_coverage_by_file).to eq(line: 80)
      end

      it "minimum_per_file with only: suggests the path target" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_file 100, only: "app/x.rb" } }

        expect(stderr).to include(%(`minimum 100, per: "app/x.rb"`))
        expect(config.minimum_coverage_by_file_overrides).to eq("app/x.rb" => {line: 100})
      end

      it "minimum_per_group warns with the group target replacement and still stores" do
        stderr = capture_stderr { config.coverage(:line) { minimum_per_group 95, only: "Models" } }

        expect(stderr).to include(%(`minimum 95, per: group("Models")`))
        expect(config.minimum_coverage_by_group).to eq("Models" => {line: 95})
      end

      it "maximum_missed_per_file warns and still stores, keyword form included" do
        stderr = capture_stderr { config.coverage :line, maximum_missed_per_file: 5 }

        expect(stderr).to include("`maximum_missed 5, per: :file`")
        expect(config.maximum_missed_per_file).to eq(line: 5)
      end

      # Every per-file setter validates its criterion and its value
      # before storing anything, so a typo fails at configuration time
      # rather than at the exit check.
      it "refuses a per-file floor for a criterion that is not enabled" do
        expect { config.send(:store_minimum_per_file, :branch, 80, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
      end

      # A floor above what coverage can reach is a warning rather than a
      # refusal: it can never pass, but it is not malformed.
      it "warns about a per-file floor above what coverage can reach" do
        stderr = capture_stderr { config.send(:store_minimum_per_file, :line, 101, nil) }

        expect(stderr).to eq("The coverage you set for minimum_coverage_by_file is greater than 100%\n")
      end

      it "refuses a per-file miss cap for a criterion that is not enabled" do
        expect { config.send(:store_maximum_missed_per_file, :branch, 5, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
      end

      it "refuses a per-file miss cap that is not a count of misses" do
        expect { config.send(:store_maximum_missed_per_file, :line, -1, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /non-negative integer count/)
        expect { config.send(:store_maximum_missed_per_file, :line, 1.5, nil) }
          .to raise_error(SimpleCov::ConfigurationError, /non-negative integer count/)
      end

      it "minimum_per_file still rejects a non-String/Regexp only: target" do
        capture_stderr do
          expect { config.coverage(:line) { minimum_per_file 100, only: :line } }
            .to raise_error(SimpleCov::ConfigurationError, /must be a String path or Regexp/)
        end
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

    context "when set via the legacy attr_writer" do
      before { config.print_error_status = false }

      it "reads back the assigned value" do
        expect(config.print_errors).to be false
      end
    end

    # Turning it back on has to write, not read: only the no-argument
    # call is a getter, and `true` is both a legitimate value and the
    # default it would otherwise be confused with.
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

    # A path is a path whatever kind of String it is.
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

    # Inspected, so the refused value is quoted the way it was written
    # rather than flattened into the sentence.
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

  # Ruby 3.2 and later answer for themselves; older runtimes cannot be
  # asked, and the historical engine check stands in. That fallback is
  # unreachable on the Ruby this suite runs, so it is reached by taking
  # the question away.
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
    # Loading this file on its own leaves Coverage undefined, so the
    # question loads it first rather than assuming a caller did.
    it "loads Coverage before asking it anything" do
      allow(config).to receive(:load_coverage).and_call_original

      config.coverage_criterion_supported?(:branches)

      expect(config).to have_received(:load_coverage)
    end

    it "answers whatever the runtime says, either way" do
      allow(Coverage).to receive(:supported?).with(:branches).and_return(true)
      expect(config.coverage_criterion_supported?(:branches)).to be true

      allow(Coverage).to receive(:supported?).with(:branches).and_return(false)
      expect(config.coverage_criterion_supported?(:branches)).to be false
    end

    context "when the runtime cannot be asked" do
      before do
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:supported?).and_return(false)
      end

      # Stubbed like the JRuby example below, because the answer differs
      # by engine and the suite really runs on more than one.
      it "supports the measured criteria" do
        stub_const("RUBY_ENGINE", "ruby")

        expect(config.coverage_criterion_supported?(:line)).to be true
        expect(config.coverage_criterion_supported?(:branch)).to be true
      end

      # `:eval` arrived after those Rubies, so there is nothing to
      # support it with.
      it "does not support eval" do
        expect(config.coverage_criterion_supported?(:eval)).to be false
      end

      it "supports nothing on JRuby, which never emitted this data" do
        stub_const("RUBY_ENGINE", "jruby")

        expect(config.coverage_criterion_supported?(:line)).to be false
        expect(config.coverage_criterion_supported?(:eval)).to be false
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

    # Every underscore becomes a space, not just the first, and only the
    # first letter is touched: a name derived from a directory should
    # read like a title without rewriting the words in it.
    it "spaces every underscore and leaves the rest of the case alone" do
      config.root("/Code/my_awesome_API_app")
      expect(config.project_name).to eq("My awesome api app")
    end

    it "takes a name given to it" do
      config.root("/Code/my_app")
      expect(config.project_name("Chosen")).to eq("Chosen")
      expect(config.project_name).to eq("Chosen")
    end

    # A getter must not overwrite a name already chosen, and a
    # non-String argument is not a name: neither may quietly replace one.
    it "keeps the name it was given when read again or handed a non-name" do
      config.project_name("Chosen")
      expect(config.project_name(nil)).to eq("Chosen")
      expect(config.project_name(:symbol)).to eq("Chosen")
      expect(config.project_name).to eq("Chosen")
    end

    it "derives a name once and keeps answering with it" do
      config.root("/Code/my_app")
      derived = config.project_name
      config.root("/Code/other_app")
      expect(config.project_name).to eq(derived)
    end

    # Any String will do, including one a caller built by subclassing it.
    it "takes a name given as a String subclass" do
      config.project_name(Class.new(String).new("Chosen"))

      expect(config.project_name).to eq("Chosen")
    end

    it "renames over a derived name" do
      config.root("/Code/my_app")
      expect(config.project_name).to eq("My app")
      expect(config.project_name("Renamed")).to eq("Renamed")
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
      capture_stderr { config.current_nocov_token("skippit") }

      expect(config.current_nocov_token).to eq "skippit"
    end

    # A token already set is not frozen: passing a new one replaces it,
    # while passing nothing keeps reading the one in force.
    it "replaces a token already set" do
      config.current_nocov_token("first")
      expect(config.current_nocov_token("second")).to eq "second"
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

      it "reserves Ungrouped for files that match no configured group" do
        config.group "Models", "app/models"

        # The name is quoted in the message, so a group called
        # "Ungrouped is fine" is not mistaken for the reserved one.
        expect { config.group "Ungrouped", // }
          .to raise_error(SimpleCov::ConfigurationError,
                          %("Ungrouped" is reserved for files that do not match a configured group))
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

      it "rejects the reserved Ungrouped name" do
        expect do
          capture_stderr { config.add_group "Ungrouped", // }
        end.to raise_error(SimpleCov::ConfigurationError, /reserved/)
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

      # Two workers is already a parallel run: the inference is about
      # whether anything else is doing the merging, not about scale.
      it "infers false for a two-worker run, the smallest parallel one" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "2"
        two_workers = Class.new(SimpleCov::ParallelAdapters::Base) do
          def self.expected_worker_count
            2
          end
        end
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(two_workers)

        expect(capture_stderr { config.finalize_merge }).to include("[DEPRECATION]").or include("")
        expect(config.finalize_merge).to be false
      end

      # Either variable on its own says a parallel worker is running.
      %w[TEST_ENV_NUMBER PARALLEL_TEST_GROUPS].each do |variable|
        it "recognises a worker environment from #{variable} alone" do
          ENV[variable] = "1"
          config.merging true
          config.coverage_dir "coverage/turbo_tests/1"
          allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

          capture_stderr { expect(config.finalize_merge).to be false }
        end
      end

      # A coverage directory set explicitly to the default one is not a
      # custom destination: nothing about it says another process is
      # collating.
      it "does not infer false when the explicit destination is the default one" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)

        expect(config.finalize_merge).to be true
      end

      # The warning is for the inference that turns finalization off; an
      # inference that leaves it on has nothing to say.
      it "colours the inference warning, so it is not lost in the run's output" do
        ENV["TEST_ENV_NUMBER"] = "1"
        ENV["PARALLEL_TEST_GROUPS"] = "3"
        config.merging true
        config.coverage_dir "coverage/turbo_tests/1"
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(adapter)
        allow(SimpleCov::Color).to receive(:enabled?).and_return(true)

        expect(capture_stderr { config.finalize_merge }).to start_with("\e[33m")
      end

      it "stays silent when it infers that this process should finalize" do
        config.merging true
        allow(SimpleCov::ParallelAdapters).to receive(:current).and_return(nil)

        expect(capture_stderr { expect(config.finalize_merge).to be true }).to be_empty
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

      it "warns and names `merging` as the replacement" do
        stderr = capture_stderr { config.use_merging(false) }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`SimpleCov.use_merging`")
        expect(stderr).to include("`SimpleCov.merging`")
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
          expect(config.view_coverage?).to be true
        end

        it "hands out a fresh copy of the default, not the frozen constant" do
          config.cover_views << "app/components/**/*.erb"

          expect(SimpleCov::Configuration::DEFAULT_VIEW_GLOBS).to eq(["app/views/**/*.{erb,haml,slim}"])
        end
      end

      context "when the runtime has no eval coverage" do
        before { allow(config).to receive(:coverage_for_eval_supported?).and_return(false) }

        # Templates would come back empty rather than at 0%, so the report is
        # better off without them than with a wall of zeroes that means
        # "unmeasurable" instead of "untested".
        it "warns and leaves view coverage off" do
          stderr = capture_stderr { config.cover_views }

          expect(stderr).to include("Coverage for eval is not available")
          expect(config.view_coverage?).to be false
        end
      end

      it "is off until asked for" do
        expect(config.view_globs).to be_nil
        expect(config.view_coverage?).to be false
      end
    end

    describe "#maximum_missed and #maximum_missed_per_file" do
      it "default to empty (disabled)" do
        expect(config.maximum_missed).to eq({})
        expect(config.maximum_missed_per_file).to eq({})
        expect(config.maximum_missed_per_file_overrides).to eq({})
      end

      it "target the primary criterion when given a bare count" do
        config.maximum_missed 12
        capture_stderr { config.maximum_missed_per_file 5 }

        expect(config.maximum_missed).to eq(line: 12)
        expect(config.maximum_missed_per_file).to eq(line: 5)
      end

      # The suffixed flat setter is deprecated in favor of the `per:`
      # axis; the reader stays, feeding enforcement.
      it "deprecate the flat maximum_missed_per_file setter with a copy-pastable replacement" do
        config.enable_coverage :branch
        stderr = capture_stderr { config.maximum_missed_per_file line: 5, branch: 2 }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("coverage(:line) { maximum_missed 5, per: :file }")
        expect(stderr).to include("coverage(:branch) { maximum_missed 2, per: :file }")
        expect(config.maximum_missed_per_file).to eq(line: 5, branch: 2)
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
          .to raise_error(SimpleCov::ConfigurationError, /non-negative integer/)
      end

      it "reject a non-integer count" do
        expect { config.coverage(:line) { maximum_missed 2.5, per: :file } }
          .to raise_error(SimpleCov::ConfigurationError, /non-negative integer/)
      end
    end

    describe "the coverage block's maximum_missed verb" do
      after { config.clear_coverage_criteria }

      it "stores caps for the block's criterion, suite-wide and per file" do
        config.coverage :branch do
          maximum_missed 3
          maximum_missed 1, per: :file
        end

        expect(config.maximum_missed).to eq(branch: 3)
        expect(config.maximum_missed_per_file).to eq(branch: 1)
      end

      it "takes per-path override targets" do
        config.coverage :line do
          maximum_missed 5, per: :file
          maximum_missed 0, per: "lib/critical.rb"
        end

        expect(config.maximum_missed_per_file).to eq(line: 5)
        expect(config.maximum_missed_per_file_overrides).to eq("lib/critical.rb" => {line: 0})
      end

      it "works as a one-liner keyword" do
        config.coverage :method, maximum_missed: 2

        expect(config.maximum_missed).to eq(method: 2)
      end

      # The enforcement for group-scoped miss caps doesn't exist yet, so
      # the target is refused rather than silently stored (see
      # docs/Roadmap.md).
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
      it "default to 100 entries measured against the last run" do
        expect(config.history_limit).to eq(100)
        expect(config.drop_baseline).to eq(:last_run)
      end

      it "take a new limit, zero disabling recording" do
        config.history_limit 10
        expect(config.history_limit).to eq(10)

        config.history_limit 0
        expect(config.history_limit).to eq(0)
      end

      it "reject a negative or fractional limit" do
        expect { config.history_limit(-1) }.to raise_error(SimpleCov::ConfigurationError, /non-negative/)
        expect { config.history_limit(1.5) }.to raise_error(SimpleCov::ConfigurationError, /non-negative/)
      end

      it "take the median and branch baselines" do
        config.drop_baseline :median
        expect(config.drop_baseline).to eq(:median)

        config.drop_baseline :branch
        expect(config.drop_baseline).to eq(:branch)
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

      it "accepts :raise and :warn" do
        config.deprecations :raise
        expect(config.deprecations).to eq(:raise)

        config.deprecations :warn
        expect(config.deprecations).to eq(:warn)
      end

      # Deliberately no :silence mode: a deprecation you cannot see is a
      # migration you never make.
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

      it "returns nil when no baseline file exists under root" do
        Dir.mktmpdir do |dir|
          config.root(dir)
          expect(config.baseline).to be_nil
        end
      end

      it "reads the baseline file relative to root, once per resolved path" do
        Dir.mktmpdir do |dir|
          config.root(dir)
          File.write(File.join(dir, ".simplecov_baseline.yml"), "lib/foo.rb: 41.2\n")

          expect(config.baseline.floor_for("lib/foo.rb", :line)).to have_attributes(percent: 41.2, missed: nil)
          expect(config.baseline).to equal(config.baseline)
        end
      end

      it "re-reads when the configured path changes" do
        Dir.mktmpdir do |dir|
          config.root(dir)
          File.write(File.join(dir, "floors.yml"), "lib/foo.rb: 41.2\n")

          expect(config.baseline).to be_nil
          config.baseline_file "floors.yml"
          expect(config.baseline.covers?("lib/foo.rb", :line)).to be true
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
      # Deprecated: every call warns via SimpleCov::Deprecation. Silence it
      # here (the dedicated example below asserts the warning) so it doesn't
      # trip the suite's app-warning guard. The methods are still exercised,
      # so they stay covered.
      before { allow(SimpleCov::Deprecation).to receive(:warn) }

      it_behaves_like "setting coverage expectations", :minimum_coverage_by_file

      it "warns with the equivalent `coverage` configuration built from the real arguments" do
        config.minimum_coverage_by_file line: 70, "app/x.rb" => 100
        expect(SimpleCov::Deprecation).to have_received(:warn).with(
          a_string_including(
            "`SimpleCov.minimum_coverage_by_file` is deprecated",
            'coverage(:line) { minimum 70, per: :file; minimum 100, per: "app/x.rb" }'
          )
        )
      end

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
      # Deprecated: every call warns via SimpleCov::Deprecation, and an
      # over-100% value warns via the config itself. Silence both here (the
      # dedicated examples below assert each) so they don't trip the suite's
      # app-warning guard. The method is still exercised, so it stays covered.
      before do
        allow(config).to receive(:warn)
        allow(SimpleCov::Deprecation).to receive(:warn)
      end

      after do
        config.clear_coverage_criteria
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
        expect(SimpleCov::Deprecation).to have_received(:warn).with(
          a_string_including(
            "`SimpleCov.minimum_coverage_by_group` is deprecated",
            'coverage(:line) { minimum 80, per: group("Models") }'
          )
        )
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

    describe "the coverage block's ignore verb" do
      after { config.clear_coverage_criteria }

      it "defaults both criteria to empty" do
        expect(config.ignored_branches).to eq []
        expect(config.ignored_methods).to eq []
      end

      it "stores branch tokens for coverage :branch" do
        config.coverage(:branch) { ignore :implicit_else, :eval_generated }

        expect(config.ignored_branch?(:implicit_else)).to be true
        expect(config.ignored_branch?(:eval_generated)).to be true
      end

      it "stores method tokens for coverage :method" do
        config.coverage(:method) { ignore :eval_generated }

        expect(config.ignored_methods).to eq [:eval_generated]
        expect(config.ignored_method?(:eval_generated)).to be true
      end

      it "unions and deduplicates across calls" do
        config.coverage(:branch) { ignore :implicit_else }
        config.coverage(:branch) { ignore :implicit_else } # duplicate is a no-op

        expect(config.ignored_branches).to eq [:implicit_else]
      end

      it "raises on an unknown token, naming the supported ones" do
        expect { config.coverage(:branch) { ignore :implict_else } }
          .to raise_error(SimpleCov::ConfigurationError,
                          /branch type :implict_else.*Supported values are \[:implicit_else, :eval_generated\]/m)
        expect { config.coverage(:method) { ignore :nope } }
          .to raise_error(SimpleCov::ConfigurationError,
                          /Unsupported method type :nope.*Supported values are \[:eval_generated\]/m)
      end

      # Line entries have no synthetic types to drop, so there is
      # nothing for `ignore` to mean there.
      it "rejects criteria without ignorable entry types" do
        expect { config.coverage(:line) { ignore :eval_generated } }
          .to raise_error(SimpleCov::ConfigurationError, /`ignore` is supported for `coverage :branch`/)
      end

      it "works as a one-liner keyword, single token or Array" do
        config.coverage :method, ignore: :eval_generated
        expect(config.ignored_method?(:eval_generated)).to be true

        other = config_class.new
        other.coverage :branch, ignore: %i[implicit_else eval_generated]
        expect(other.ignored_branches).to eq %i[implicit_else eval_generated]
      end
    end

    describe "#ignore_branches and #ignore_methods (deprecated)" do
      it "warn with the coverage-block replacement and still store" do
        stderr = capture_stderr { config.ignore_branches :implicit_else, :eval_generated }

        expect(stderr).to include("[DEPRECATION]")
        expect(stderr).to include("`coverage(:branch) { ignore :implicit_else, :eval_generated }`")
        expect(config.ignored_branches).to eq %i[implicit_else eval_generated]

        stderr = capture_stderr { config.ignore_methods :eval_generated }
        expect(stderr).to include("`coverage(:method) { ignore :eval_generated }`")
        expect(config.ignored_methods).to eq [:eval_generated]
      end

      # Unlike the coverage block, whose criterion naming enables the
      # criterion, the legacy setters record without enabling, and some
      # configurations depend on setting the filter before (or without)
      # enabling. That behavior rides out the deprecation period.
      it "store the setting without enabling the criterion" do
        expect(config.coverage_criteria).to contain_exactly :line
        capture_stderr { config.ignore_branches :implicit_else }

        expect(config.coverage_criteria).to contain_exactly :line
        expect(config.ignored_branch?(:implicit_else)).to be true
      end

      it "stay order-independent with respect to enable_coverage" do
        capture_stderr { config.ignore_branches :implicit_else }
        config.enable_coverage :branch

        expect(config.coverage_criteria).to include :branch
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
        previous = SimpleCov.current_run
        SimpleCov.current_run = SimpleCov::CurrentRun.new
        example.run
      ensure
        SimpleCov.current_run = previous
      end

      it "defaults to 0 and increments monotonically" do
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

      # `simplecov watch` extends the merge window of its child runs
      # through the environment, since a subset re-run merged under the
      # default ten minutes would erode the report over a long session.
      it "honors SIMPLECOV_MERGE_TIMEOUT over the configured value" do
        config.merge_timeout(120)
        stub_const("ENV", ENV.to_hash.merge("SIMPLECOV_MERGE_TIMEOUT" => "86400"))
        expect(config.merge_timeout).to eq(86_400)
      end

      it "ignores a malformed SIMPLECOV_MERGE_TIMEOUT" do
        stub_const("ENV", ENV.to_hash.merge("SIMPLECOV_MERGE_TIMEOUT" => "soon"))
        expect(config.merge_timeout).to eq(600)
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

  # Setters that answer with what they stored, which is what a
  # configuration file reads back and what the DSL chains from.
  describe "what the stores answer" do
    after { config.clear_coverage_criteria }

    it "answers the cover filters after adding one" do
      expect(config.cover("lib/**/*.rb")).to be(config.cover_filters)
      expect(config.cover_filters.size).to eq(1)
    ensure
      config.cover_filters.clear
    end

    it "answers the formatters after setting them" do
      expect(config.formatters(SimpleCov::Formatter::SimpleFormatter)).to be_a(Object)
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

    # The timeout is memoized so a later read does not fall back to the
    # default when the environment carries none.
    it "keeps the timeout it worked out for later reads" do
      config.merge_timeout

      expect(config.instance_variable_get(:@merge_timeout)).to eq(600)
    ensure
      config.remove_instance_variable(:@merge_timeout) if config.instance_variable_defined?(:@merge_timeout)
    end

    # A threshold table can carry a criterion with nothing set for it,
    # which is not a threshold above 100%.
    it "passes over a criterion with no threshold at all" do
      allow(SimpleCov::Deprecation).to receive(:warn)

      expect { config.coverage(:line) { minimum_per_file nil, only: "lib/a.rb" } }.not_to raise_error
    end
  end

  # Every deprecation says the same three things: that it is one, what
  # to write instead, and the setting it came from. The wrapper is what
  # makes the first of those true.
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

  # A path or a pattern is taken by kind wherever a per-file target is
  # accepted, and shown as it was written when it is neither.
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

  # The remaining small answers: each is read by something else, and
  # each had nothing saying what it answers.
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

    it "reads the baseline once per resolved path" do
      allow(SimpleCov::Baseline).to receive(:read).and_return(SimpleCov::Baseline.new({}))

      first = config.baseline

      expect(config.baseline).to be(first)
      expect(SimpleCov::Baseline).to have_received(:read).once
    ensure
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

    it "clears the filters to an empty chain, not to nothing" do
      config.skip "vendor"

      expect(config.clear_filters).to eq([])
      expect(config.filters).to eq([])
    end

    it "asks the runtime whether it can measure eval'd code, and believes the yes" do
      allow(Coverage).to receive(:supported?).with(:eval).and_return(true)

      expect(config.coverage_for_eval_supported?).to be true
    end

    it "answers that a branch type nobody ignored is not ignored" do
      config.coverage(:branch) { ignore :implicit_else }

      expect(config.ignored_branch?(:implicit_else)).to be true
      expect(config.ignored_branch?(:eval_generated)).to be false
    end

    it "answers the ignored types it stored" do
      stored = nil
      config.coverage(:branch) { stored = ignore :implicit_else }

      expect(stored).to eq([:implicit_else])
    end

    it "takes a merge timeout in seconds, and ignores one that is not" do
      config.merge_timeout 120
      expect(config.merge_timeout).to eq(120)

      config.merge_timeout "600"
      expect(config.merge_timeout).to eq(120)
    ensure
      config.remove_instance_variable(:@merge_timeout) if config.instance_variable_defined?(:@merge_timeout)
    end

    # Ownership needs both halves: this process finalizing, and it being
    # the last one out.
    it "owns the merge only when it finalizes and is the final process" do
      allow(config).to receive_messages(collating_result?: false, final_result_process?: true)
      config.finalize_merge false

      expect(config.merge_finalization_owner?).to be false

      config.finalize_merge true
      expect(config.merge_finalization_owner?).to be true
    ensure
      %i[@finalize_merge @finalize_merge_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end
  end

  # Groups are named filters, and both spellings validate the name and
  # keep the filter that goes with it.
  describe "naming a group" do
    after { config.groups.clear }

    it "takes a name and a block, with no filter argument at all" do
      config.group("Models") { |source_file| source_file.filename.include?("model") }

      expect(config.groups.keys).to eq(["Models"])
      expect(config.groups.fetch("Models")
                   .matches?(instance_double(SimpleCov::SourceFile, filename: "app/models/a.rb"))).to be true
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

  # What the `coverage` DSL and the formats setter answer, which is what
  # a configuration file chains from.
  describe "what the setters answer" do
    after { config.clear_coverage_criteria }

    it "answers the formatters it resolved, and the ones it has when asked for none" do
      expect(config.formats).to eq([])

      expect(config.formats(:simple)).to eq(config.formatters)
      expect(config.formats.size).to eq(1)
      expect(config.formatters.size).to eq(1)
    ensure
      config.instance_variable_set(:@formatter, nil)
    end

    # Either half being set outright makes the destination explicit.
    it "counts a path set outright, and a directory set outright, each on its own" do
      expect(config.send(:explicit_coverage_destination?)).to be_falsey

      config.coverage_dir "elsewhere"
      expect(config.send(:explicit_coverage_destination?)).to be_truthy

      config.remove_instance_variable(:@coverage_dir_explicit)
      config.coverage_path File.expand_path("tmp/elsewhere")
      expect(config.send(:explicit_coverage_destination?)).to be_truthy
    ensure
      %i[@coverage_dir @coverage_path @coverage_dir_explicit @coverage_path_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end
  end

  # Odds and ends the rest of the configuration reads: each answers
  # something a mutation could replace with a constant nobody would
  # notice from a suite that always configures these first.
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

    # View coverage needs both halves: somewhere to look, and the eval
    # measurement that sees compiled templates at all.
    it "measures view coverage only with globs and eval coverage both" do
      allow(config).to receive(:coverage_for_eval_enabled?).and_return(true)
      expect(config.view_coverage?).to be false

      config.cover_views "app/views/**/*.erb"
      allow(config).to receive(:coverage_for_eval_enabled?).and_return(false)
      expect(config.view_coverage?).to be false

      allow(config).to receive(:coverage_for_eval_enabled?).and_return(true)
      expect(config.view_coverage?).to be true
    ensure
      config.instance_variable_set(:@view_globs, nil)
    end

    it "asks the runtime whether it can measure eval'd code" do
      allow(Coverage).to receive(:supported?).with(:eval).and_return(false)

      expect(config.coverage_for_eval_supported?).to be false
    end

    it "registers a block filter that decides for itself" do
      registered = config.cover { |source_file| source_file.filename.end_with?("a.rb") }

      expect(registered).to be(config.cover_filters)
      expect(config.cover_filters.size).to eq(1)
      expect(config.cover_filters.first.matches?(instance_double(SimpleCov::SourceFile, filename: "lib/a.rb")))
        .to be true
    ensure
      config.cover_filters.clear
    end
  end

  # Group thresholds read back as a hash, and the DSL's `per: group(...)`
  # writes the same store the flat setter does.
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

    # The deprecated flat setter renders the block form as its
    # replacement, one line per group and criterion.
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

  # Line coverage leads the report whenever it is measured, whatever
  # order the criteria were enabled in.
  describe "which criterion leads" do
    after { config.clear_coverage_criteria }

    it "prefers line coverage even when another criterion was enabled first" do
      config.disable_coverage :line
      config.enable_coverage :branch
      config.enable_coverage :line

      expect(config.coverage_criteria.first).to eq(:branch)
      expect(config.primary_coverage).to eq(:line)
    end
  end

  # The at_exit hook is what formats the report, and it belongs to
  # whichever process is finalizing the merge.
  describe "#at_exit" do
    after { config.instance_variable_set(:@at_exit, nil) }

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

    # Collation can leave this process with nothing to format.
    it "does nothing when there is no result to format" do
      allow(SimpleCov).to receive_messages(result: nil, merge_finalization_owner?: true, result?: true)

      expect { config.at_exit.call }.not_to raise_error
    end

    it "answers a hook that does nothing at all outside a session" do
      allow(SimpleCov).to receive_messages(result?: false, result: nil)
      allow(Coverage).to receive(:running?).and_return(false)

      expect(config.at_exit.call).to be_nil
      expect(SimpleCov).not_to have_received(:result)
    end

    it "keeps the block it was given" do
      hook = proc { :mine }

      expect(config.at_exit(&hook)).to be(hook)
      expect(config.at_exit).to be(hook)
    end
  end

  # Ignoring synthetic entries is per criterion, and the list is a set:
  # naming a type twice is naming it once.
  describe "ignoring synthetic entries" do
    after { config.clear_coverage_criteria }

    it "keeps one entry per type, however it is spelled" do
      ignored = nil
      config.coverage(:method) { ignore :eval_generated }
      config.coverage(:method) { ignored = ignore [:eval_generated] }

      expect(ignored).to eq([:eval_generated])
      expect(config.ignored_methods).to eq([:eval_generated])
    end

    it "refuses to ignore anything for a criterion that has nothing to ignore" do
      expect { config.coverage(:line) { ignore :eval_generated } }
        .to raise_error(SimpleCov::ConfigurationError,
                        "`ignore` is supported for `coverage :branch` and `coverage :method`, not :line")
    end
  end

  # The deprecation warnings carry a copy-pastable replacement, so what
  # they render is part of the interface.
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

  # Answers other parts of the configuration lean on, each of which a
  # mutation could replace with a plausible constant.
  describe "what the configuration works out for itself" do
    after { config.clear_coverage_criteria }

    it "leads with line coverage while it is measured, and with what is left when it is not" do
      expect(config.primary_coverage).to eq(:line)

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

    # A configuration loaded on its own has no Coverage to ask, which
    # is not something a suite that measures coverage can be.
    it "has nothing to do at exit when there is no Coverage to ask" do
      allow(SimpleCov).to receive(:result?).and_return(false)
      hide_const("Coverage")

      expect(config.send(:active_session?)).to be false
    end

    # A destination is custom when it was set outright and is not the
    # folder the defaults would have produced anyway.
    it "tells a custom coverage destination from the default one" do
      expect(config.send(:explicit_custom_coverage_destination?)).to be false

      config.root "tmp/destination"
      config.coverage_dir "coverage"
      expect(config.send(:explicit_custom_coverage_destination?)).to be false

      config.coverage_dir "elsewhere"
      expect(config.send(:explicit_custom_coverage_destination?)).to be true

      # A destination that differs from the default but that nobody set
      # is not a custom one: something else moved the root under it.
      config.remove_instance_variable(:@coverage_dir_explicit)
      expect(config.send(:explicit_custom_coverage_destination?)).to be false
    ensure
      %i[@root @coverage_dir @coverage_path @coverage_dir_explicit @coverage_path_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end

    # Reading the directory is not setting it: only an argument makes
    # the destination an explicit one.
    it "does not call a directory explicit for having been read" do
      config.coverage_dir

      expect(config.send(:explicit_coverage_destination?)).to be_falsey
    ensure
      %i[@coverage_dir @coverage_dir_explicit].each do |ivar|
        config.remove_instance_variable(ivar) if config.instance_variable_defined?(ivar)
      end
    end

    it "leaves a foreign object in the filter chain alone" do
      config.filters << Object.new
      config.skip "vendor"

      expect(config.remove_filter("vendor")).to be true
      expect(config.remove_filter("vendor")).to be false
      expect(config.filters.size).to eq(1)
    ensure
      config.clear_filters
    end
  end

  # The root and the coverage directory are memoized, and each is the
  # other half of the path the report is written to: setting either has
  # to drop a path computed from the old pair, unless that path was set
  # outright.
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

    it "resolves a root it is given against the working directory" do
      config.root "tmp/somewhere"

      expect(config.root).to eq(File.expand_path("tmp/somewhere"))
    end

    it "keeps answering the root it was given" do
      config.root "tmp/somewhere"

      expect(config.root).to eq(File.expand_path("tmp/somewhere"))
      expect(config.root(nil)).to eq(File.expand_path("tmp/somewhere"))
    end

    it "drops a coverage path computed from the old root" do
      config.root "tmp/first"
      first = config.coverage_path

      config.root "tmp/second"

      expect(config.coverage_path).not_to eq(first)
      expect(config.coverage_path).to eq(File.join(File.expand_path("tmp/second"), "coverage"))
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

    # A path set outright is not derived from either half, so neither
    # setting a root nor a directory may drop it.
    it "keeps a coverage path that was set outright" do
      config.root "tmp/first"
      config.coverage_path File.expand_path("tmp/explicit")

      config.root "tmp/second"

      expect(config.coverage_path).to eq(File.expand_path("tmp/explicit"))
    ensure
      FileUtils.rm_rf([File.expand_path("tmp/first"), File.expand_path("tmp/second"),
                       File.expand_path("tmp/explicit")])
    end
  end

  # The getters and setters that share one method, where the sentinel
  # tells "read me" from "write me this", and where a mutation can turn
  # a write into a read of something else.
  describe "reading and writing the formatter" do
    after { config.instance_variable_set(:@formatter, nil) }

    it "answers no formatters before one is set, and the one after" do
      expect(config.formatters).to eq([])

      config.formatters SimpleCov::Formatter::SimpleFormatter

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
      expect(config.formatters.size).to eq(1)
    end

    it "answers what it was handed, so a chained call sees it" do
      formatters = [SimpleCov::Formatter::SimpleFormatter]

      expect(config.formatters(formatters)).to be(formatters)
    end

    # The documented way to turn formatting off entirely.
    it "opts out of formatting when handed an empty list" do
      config.formatters SimpleCov::Formatter::SimpleFormatter
      expect(config.formatters.size).to eq(1)

      config.formatters = []

      expect(config.formatter).to be_nil
      expect(config.formatters).to eq([])
    end

    it "keeps the formatter it is handed, and normalises false to none at all" do
      config.formatter SimpleCov::Formatter::SimpleFormatter
      expect(config.formatter).to be(SimpleCov::Formatter::SimpleFormatter)

      config.formatter false
      expect(config.formatter).to be_nil
    end

    it "resolves the built-in format names, and refuses the rest" do
      config.formats :simple

      expect(config.formatter.new.formatters).to eq([SimpleCov::Formatter::SimpleFormatter])
      expect(config.formats).to eq(config.formatters)
      expect { config.formats :yaml }
        .to raise_error(SimpleCov::ConfigurationError, /Unknown format :yaml/)
    end

    # A class or instance passes through as it stands: only names are
    # looked up.
    it "leaves a formatter that is not a name alone" do
      formatter = SimpleCov::Formatter::SimpleFormatter.new

      expect(config.send(:resolve_format, formatter)).to be(formatter)
    end

    it "answers the HTML formatter for :html, having required it" do
      expect(config.send(:resolve_format, :html)).to eq(SimpleCov::Formatter::HTMLFormatter)
    end

    # The require is what makes :html work in a process that never
    # loaded the formatter, and only :html asks for it.
    it "loads the HTML formatter for that name and no other" do
      allow(config).to receive(:require_html_formatter)

      config.send(:resolve_format, :html)
      config.send(:resolve_format, :simple)

      expect(config).to have_received(:require_html_formatter).with(:html).once
    end
  end

  # An expected coverage is a minimum and a maximum at once, and asking
  # for it without one is asking what the minimum is.
  describe "#expected_coverage" do
    after { config.clear_coverage_criteria }

    it "answers the minimum when it is not given one" do
      config.minimum_coverage 80

      expect(config.expected_coverage).to eq(line: 80)
    end

    it "pins coverage from both ends when it is given one" do
      config.expected_coverage 90

      expect(config.minimum_coverage).to eq(line: 90)
      expect(config.maximum_coverage).to eq(line: 90)
    end
  end

  # Small answers the rest of the configuration leans on, each of which
  # a mutation could hand back a plausible constant instead.
  describe "what the configuration answers about itself" do
    it "keeps the primary criterion when a different one is disabled" do
      config.enable_coverage :branch
      config.enable_coverage :method
      config.primary_coverage :branch

      config.disable_coverage :method

      expect(config.primary_coverage).to eq(:branch)
    ensure
      config.clear_coverage_criteria
    end

    it "answers no branch or method coverage on a runtime that cannot measure it" do
      config.enable_coverage :branch
      config.enable_coverage :method
      allow(Coverage).to receive(:supported?).and_return(false)

      expect(config.branch_coverage?).to be false
      expect(config.method_coverage?).to be false
    ensure
      config.clear_coverage_criteria
    end

    it "answers that a method type nobody ignored is not ignored" do
      config.coverage(:method) { ignore :eval_generated }

      expect(config.ignored_method?(:eval_generated)).to be true
      expect(config.ignored_method?(:accessor)).to be false
    ensure
      config.clear_coverage_criteria
    end

    it "keeps a filter that has no argument to compare" do
      config.filters << SimpleCov::BlockFilter.new(->(source_file) { source_file.lines.count < 5 })
      config.skip "vendor"

      expect(config.remove_filter("vendor")).to be true
      expect(config.filters.size).to eq(1)
    ensure
      config.clear_filters
    end

    it "answers a profiles registry, not the registry class" do
      expect(config.profiles).to be_a(SimpleCov::Profiles)
    end

    # The hook belongs to SimpleCov, whoever holds the configuration it
    # came from: a forked child reconfigures the real thing.
    it "reconfigures SimpleCov itself when the fork hook fires" do
      allow(SimpleCov).to receive(:command_name).and_return("Parent Suite")
      allow(SimpleCov).to receive(:print_errors)
      allow(SimpleCov).to receive(:formatter)
      allow(SimpleCov).to receive(:minimum_coverage)
      allow(SimpleCov).to receive(:start)

      config.at_fork.call(123)

      expect(SimpleCov).to have_received(:command_name).with(/\AParent Suite \(subprocess: \d+\)\z/)
      expect(SimpleCov).to have_received(:formatter).with(SimpleCov::Formatter::SimpleFormatter)
      expect(SimpleCov).to have_received(:print_errors).with(false)
      expect(SimpleCov).to have_received(:minimum_coverage).with(0)
      expect(SimpleCov).to have_received(:start)
    end
  end

  # Everything here is about what a value's own spelling looks like in a
  # message, so the values are ones whose inspected form differs from
  # their plain one.
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

    # The count is refused before the criterion is looked at, so the
    # message names the setting the block was writing.
    it "names the block's own setting when its count is refused" do
      expect { config.coverage(:line) { maximum_missed(-1) } }
        .to raise_error(SimpleCov::ConfigurationError,
                        "maximum_missed takes a non-negative integer count of misses, got -1")
    end

    # `enabled: false` configures a criterion without measuring it, and a
    # cap on something nothing measures is a mistake worth naming.
    it "refuses a cap for a criterion the run does not measure" do
      expect { config.coverage(:branch, enabled: false) { maximum_missed 3 } }
        .to raise_error(SimpleCov::ConfigurationError, /branch, is disabled/)
    end
  end

  # A configuration error names the setting it came from and shows the
  # value it refused, inspected: an unquoted string or a bare nil in
  # that sentence is what sends someone hunting through their own config
  # for a setting they never wrote.
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

    # `only:` is the deprecated spelling of the same target, and its
    # refusal has to be as legible as the modern one.
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

  # Paths and patterns are taken by kind, not by exact class, so a
  # project handing over a String or Regexp subclass is configuring
  # SimpleCov, not confusing it.
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

    # Rational and BigDecimal are Numerics that are not Floats, and a
    # threshold is a number whatever kind of number it is.
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

    # A granularity given alone must not disturb the switch, and no
    # granularity at all must not erase the one in force.
    it "keeps the granularity it was given when called again without one" do
      config.track_tests granularity: :file
      config.track_tests

      expect(config.track_tests_granularity).to eq(:file)
      expect(config.track_tests?).to be true
    end

    describe "granularity" do
      it "defaults to per-test attribution" do
        expect(config.track_tests_granularity).to eq(:test)
      end

      it "accepts :file for one context per test file" do
        config.track_tests granularity: :file

        expect(config.track_tests?).to be true
        expect(config.track_tests_granularity).to eq(:file)
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

      # The map is built from per-line execution count deltas, which
      # oneshot mode does not produce: a line reports only its first hit
      # ever, so every later test's delta would miss it.
      it "rejects tracking under oneshot line coverage" do
        config.track_tests
        config.enable_coverage :oneshot_line

        expect { config.validate_test_tracking! }
          .to raise_error(SimpleCov::ConfigurationError, /track_tests.*line coverage/)
      end
    end
  end
end
