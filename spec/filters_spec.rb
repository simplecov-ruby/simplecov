# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::Filter do
  let(:source_file) do
    SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
  end

  it "doesn't match a new SimpleCov::StringFilter 'foobar'" do
    expect(SimpleCov::StringFilter.new("foobar")).not_to be_matches source_file
  end

  it "doesn't match a new SimpleCov::StringFilter 'some/path'" do
    expect(SimpleCov::StringFilter.new("some/path")).not_to be_matches source_file
  end

  it "matches a new SimpleCov::StringFilter 'spec/fixtures'" do
    expect(SimpleCov::StringFilter.new("spec/fixtures")).to be_matches source_file
  end

  it "matches a new SimpleCov::StringFilter 'spec/fixtures/sample.rb'" do
    expect(SimpleCov::StringFilter.new("spec/fixtures/sample.rb")).to be_matches source_file
  end

  it "matches a new SimpleCov::StringFilter 'sample.rb'" do
    expect(SimpleCov::StringFilter.new("sample.rb")).to be_matches source_file
  end

  it "matches a new SimpleCov::StringFilter 'sample' (basename without extension)" do
    expect(SimpleCov::StringFilter.new("sample")).to be_matches source_file
  end

  it "doesn't match at non-segment boundaries" do
    library_file = SimpleCov::SourceFile.new(
      File.join(SimpleCov.root, "app/models/library.rb"),
      [nil, 1, 1]
    )
    expect(SimpleCov::StringFilter.new("lib")).not_to be_matches library_file
  end

  it "doesn't match a new SimpleCov::StringFilter '.pl'" do
    expect(SimpleCov::StringFilter.new(".pl")).not_to be_matches source_file
  end

  it "doesn't match a parent directory with a new SimpleCov::StringFilter" do
    parent_dir_name = File.basename(File.expand_path("..", File.dirname(__FILE__)))
    expect(SimpleCov::StringFilter.new(parent_dir_name)).not_to be_matches source_file
  end

  it "matches a new SimpleCov::RegexFilter //fixtures//" do
    expect(SimpleCov::RegexFilter.new(%r{/fixtures/})).to be_matches source_file
  end

  it "doesn't match a new SimpleCov::RegexFilter /^fixtures//" do
    expect(SimpleCov::RegexFilter.new(%r{^fixtures/})).not_to be_matches source_file
  end

  it "matches a new SimpleCov::RegexFilter /^spec//" do
    expect(SimpleCov::RegexFilter.new(%r{^spec/})).to be_matches source_file
  end

  it "matches a SimpleCov::GlobFilter that includes the path" do
    expect(SimpleCov::GlobFilter.new("spec/fixtures/**/*.rb")).to be_matches source_file
  end

  it "doesn't match a SimpleCov::GlobFilter that excludes the path" do
    expect(SimpleCov::GlobFilter.new("lib/**/*.rb")).not_to be_matches source_file
  end

  it "doesn't match a new SimpleCov::BlockFilter that is not applicable" do
    expect(SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "foo.rb" })).not_to be_matches source_file
  end

  it "matches a new SimpleCov::BlockFilter that is applicable" do
    expect(SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "sample.rb" })).to be_matches source_file
  end

  it "matches a new SimpleCov::ArrayFilter when 'sample.rb' is passed as array" do
    expect(SimpleCov::ArrayFilter.new(["sample.rb"])).to be_matches source_file
  end

  it "doesn't match a new SimpleCov::ArrayFilter when a file path different than 'sample.rb' is passed as array" do
    expect(SimpleCov::ArrayFilter.new(["other_file.rb"])).not_to be_matches source_file
  end

  it "matches a new SimpleCov::ArrayFilter when two file paths including 'sample.rb' are passed as array" do
    expect(SimpleCov::ArrayFilter.new(["sample.rb", "other_file.rb"])).to be_matches source_file
  end

  it "doesn't match a parent directory with a new SimpleCov::ArrayFilter" do
    parent_dir_name = File.basename(File.expand_path("..", File.dirname(__FILE__)))
    expect(SimpleCov::ArrayFilter.new([parent_dir_name])).not_to be_matches source_file
  end

  it "matches a new SimpleCov::ArrayFilter when /sample.rb/ is passed as array" do
    expect(SimpleCov::ArrayFilter.new([/sample.rb/])).to be_matches source_file
  end

  it "doesn't match a new SimpleCov::ArrayFilter when a file path different than /sample.rb/ is passed as array" do
    expect(SimpleCov::ArrayFilter.new([/other_file.rb/])).not_to be_matches source_file
  end

  it "matches a new SimpleCov::ArrayFilter when a block is passed as array and returns true" do
    expect(SimpleCov::ArrayFilter.new([proc { true }])).to be_matches source_file
  end

  it "doesn't match a new SimpleCov::ArrayFilter when a block that returns false is passed as array" do
    expect(SimpleCov::ArrayFilter.new([proc { false }])).not_to be_matches source_file
  end

  it "matches a new SimpleCov::ArrayFilter when a custom class that returns true is passed as array" do
    filter = Class.new(SimpleCov::Filter) do
      def matches?(_source_file)
        true
      end
    end.new(nil)
    expect(SimpleCov::ArrayFilter.new([filter])).to be_matches source_file
  end

  it "doesn't match a new SimpleCov::ArrayFilter when a custom class that returns false is passed as array" do
    filter = Class.new(SimpleCov::Filter) do
      def matches?(_source_file)
        false
      end
    end.new(nil)
    expect(SimpleCov::ArrayFilter.new([filter])).not_to be_matches source_file
  end

  context "with no filters set up and a basic source file in an array" do
    subject(:filter) do
      [SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])]
    end

    around do |example|
      prev_filters = SimpleCov.filters
      SimpleCov.filters = []
      example.run
      SimpleCov.filters = prev_filters
    end

    it 'returns 0 items after executing SimpleCov.filtered on files when using a "sample" string filter' do
      SimpleCov.skip "sample"
      expect(SimpleCov.filtered(filter).count).to be_zero
    end

    it 'returns 0 items after executing SimpleCov.filtered on files when using a "spec/fixtures" string filter' do
      SimpleCov.skip "spec/fixtures"
      expect(SimpleCov.filtered(filter).count).to be_zero
    end

    it 'returns 1 item after executing SimpleCov.filtered on files when using a "fooo" string filter' do
      SimpleCov.skip "fooo"
      expect(SimpleCov.filtered(filter).count).to eq(1)
    end

    it "returns 0 items after executing SimpleCov.filtered on files when using a block filter that returns true" do
      SimpleCov.skip(&proc { true })
      expect(SimpleCov.filtered(filter).count).to be_zero
    end

    it "returns 1 item after executing SimpleCov.filtered on files when using an always-false block filter" do
      SimpleCov.skip(&proc { false })
      expect(SimpleCov.filtered(filter).count).to eq(1)
    end

    it "returns a FileList after filtering" do
      SimpleCov.skip "fooo"
      expect(SimpleCov.filtered(filter)).to be_a SimpleCov::FileList
    end
  end

  describe "#remove_filter" do
    around do |example|
      prev_filters = SimpleCov.filters
      SimpleCov.filters = []
      example.run
      SimpleCov.filters = prev_filters
    end

    it "removes a string filter that matches by value" do
      SimpleCov.skip "spec"
      SimpleCov.skip "lib"
      expect(SimpleCov.remove_filter("spec")).to be true
      expect(SimpleCov.filters.map(&:filter_argument)).to eq(["lib"])
    end

    it "removes a regex filter that matches by value" do
      SimpleCov.skip(/\A\..*/)
      SimpleCov.skip(/\Aapp/)
      expect(SimpleCov.remove_filter(/\A\..*/)).to be true
      expect(SimpleCov.filters.map(&:filter_argument)).to eq([/\Aapp/])
    end

    it "removes every matching filter, not just the first" do
      SimpleCov.skip "spec"
      SimpleCov.skip "spec"
      SimpleCov.skip "lib"
      SimpleCov.remove_filter("spec")
      expect(SimpleCov.filters.map(&:filter_argument)).to eq(["lib"])
    end

    it "returns false when nothing matches" do
      SimpleCov.skip "spec"
      expect(SimpleCov.remove_filter("nope")).to be false
      expect(SimpleCov.filters.size).to eq(1)
    end
  end

  describe "#clear_filters" do
    around do |example|
      prev_filters = SimpleCov.filters
      SimpleCov.filters = []
      example.run
      SimpleCov.filters = prev_filters
    end

    it "empties the filter chain" do
      SimpleCov.skip "spec"
      SimpleCov.skip(/\A\..*/)
      SimpleCov.clear_filters
      expect(SimpleCov.filters).to be_empty
    end
  end

  context "with the default configuration" do
    skip "requires the default configuration" if ENV["SIMPLECOV_NO_DEFAULTS"]

    def a_file(path)
      # Treat both Unix-style `/foo` and Windows-style `C:/foo` as absolute.
      # `File.absolute_path?` alone doesn't recognize `/foo` on Windows;
      # `start_with?("/")` alone doesn't recognize drive-letter paths.
      path = File.join(SimpleCov.root, path) unless path.start_with?("/") || File.absolute_path?(path)
      SimpleCov::SourceFile.new(path, [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
    end

    context "when inside the project" do
      it "doesn't filter" do
        expect(SimpleCov.filtered([a_file("foo.rb")]).count).to eq(1)
      end

      it "filters vendor/bundle" do
        expect(SimpleCov.filtered([a_file("vendor/bundle/foo.rb")]).count).to eq(0)
      end

      it "filters hidden folders" do
        expect(SimpleCov.filtered([a_file(".semaphore-cache/lib.rb")]).count).to eq(0)
      end

      it "filters hidden files" do
        expect(SimpleCov.filtered([a_file(".hidden_config.rb")]).count).to eq(0)
      end

      it "doesn't filter hidden files further down the path" do
        expect(SimpleCov.filtered([a_file("some_dir/.sneaky.rb")]).count).to eq(1)
      end
    end

    context "when outside the project" do
      it "filters" do
        expect(SimpleCov.filtered([a_file("/other/path/foo.rb")]).count).to eq(0)
      end

      it "filters even if the sibling directory has SimpleCov.root as a prefix" do
        sibling_dir = "#{SimpleCov.root}_cache"
        expect(SimpleCov.filtered([a_file("#{sibling_dir}/foo.rb")]).count).to eq(0)
      end
    end
  end

  describe ".class_for_argument" do
    it "returns SimpleCov::StringFilter for a string" do
      expect(described_class.class_for_argument("filestring")).to eq(SimpleCov::StringFilter)
    end

    it "returns SimpleCov::RegexFilter for a regex" do
      expect(described_class.class_for_argument(/regex/)).to eq(SimpleCov::RegexFilter)
    end

    it "returns SimpleCov::ArrayFilter for an array" do
      expect(described_class.class_for_argument(%w[file1 file2])).to eq(SimpleCov::ArrayFilter)
    end
  end

  describe "#matches?" do
    it "raises NotImplementedError on the base class — subclasses must override" do
      expect { described_class.new("anything").matches?(nil) }
        .to raise_error(NotImplementedError, /not intended for direct use/)
    end
  end

  describe ".class_for_argument with an unknown filter argument type" do
    it "raises a ConfigurationError when the argument doesn't match any registered filter type" do
      expect { described_class.class_for_argument(Object.new) }
        .to raise_error(SimpleCov::ConfigurationError, /unrecognized filter type/)
    end
  end
end
