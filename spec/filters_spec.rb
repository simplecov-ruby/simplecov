require "helper"

if SimpleCov.usable?
  describe SimpleCov::SourceFile do
    subject do
      SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
    end

    it "doesn't match a new SimpleCov::StringFilter 'foobar'" do
      expect(SimpleCov::StringFilter.new("foobar")).not_to be_matches subject
    end

    it "doesn't match a new SimpleCov::StringFilter 'some/path'" do
      expect(SimpleCov::StringFilter.new("some/path")).not_to be_matches subject
    end

    it "matches a new SimpleCov::StringFilter 'spec/fixtures'" do
      expect(SimpleCov::StringFilter.new("spec/fixtures")).to be_matches subject
    end

    it "matches a new SimpleCov::StringFilter 'spec/fixtures/sample.rb'" do
      expect(SimpleCov::StringFilter.new("spec/fixtures/sample.rb")).to be_matches subject
    end

    it "matches a new SimpleCov::StringFilter 'sample.rb'" do
      expect(SimpleCov::StringFilter.new("sample.rb")).to be_matches subject
    end

    it "doesn't match a parent directory with a new SimpleCov::StringFilter" do
      parent_dir_name = File.basename(File.expand_path("..", File.dirname(__FILE__)))
      expect(SimpleCov::StringFilter.new(parent_dir_name)).not_to be_matches subject
    end

    it "matches a new SimpleCov::StringFilter '/fixtures/'" do
      expect(SimpleCov::StringFilter.new("sample.rb")).to be_matches subject
    end

    it "matches a new SimpleCov::RegexFilter /\/fixtures\//" do
      expect(SimpleCov::RegexFilter.new(/\/fixtures\//)).to be_matches subject
    end

    it "doesn't match a new SimpleCov::RegexFilter /^\/fixtures\//" do
      expect(SimpleCov::RegexFilter.new(/^\/fixtures\//)).not_to be_matches subject
    end

    it "matches a new SimpleCov::RegexFilter /^\/spec\//" do
      expect(SimpleCov::RegexFilter.new(/^\/spec\//)).to be_matches subject
    end

    it "doesn't match a new SimpleCov::BlockFilter that is not applicable" do
      expect(SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "foo.rb" })).not_to be_matches subject
    end

    it "matches a new SimpleCov::BlockFilter that is applicable" do
      expect(SimpleCov::BlockFilter.new(proc { |s| File.basename(s.filename) == "sample.rb" })).to be_matches subject
    end

    it "matches a new SimpleCov::ArrayFilter when 'sample.rb' is passed as array" do
      expect(SimpleCov::ArrayFilter.new(["sample.rb"])).to be_matches subject
    end

    it "doesn't match a new SimpleCov::ArrayFilter when a file path different than 'sample.rb' is passed as array" do
      expect(SimpleCov::ArrayFilter.new(["other_file.rb"])).not_to be_matches subject
    end

    it "matches a new SimpleCov::ArrayFilter when two file paths including 'sample.rb' are passed as array" do
      expect(SimpleCov::ArrayFilter.new(["sample.rb", "other_file.rb"])).to be_matches subject
    end

    it "doesn't match a parent directory with a new SimpleCov::ArrayFilter" do
      parent_dir_name = File.basename(File.expand_path("..", File.dirname(__FILE__)))
      expect(SimpleCov::ArrayFilter.new([parent_dir_name])).not_to be_matches subject
    end

    it "matches a new SimpleCov::ArrayFilter when /sample.rb/ is passed as array" do
      expect(SimpleCov::ArrayFilter.new([/sample.rb/])).to be_matches subject
    end

    it "doesn't match a new SimpleCov::ArrayFilter when a file path different than /sample.rb/ is passed as array" do
      expect(SimpleCov::ArrayFilter.new([/other_file.rb/])).not_to be_matches subject
    end

    it "matches a new SimpleCov::ArrayFilter when a block is passed as array and returns true" do
      expect(SimpleCov::ArrayFilter.new([proc { true }])).to be_matches subject
    end

    it "doesn't match a new SimpleCov::ArrayFilter when a block that returns false is passed as array" do
      expect(SimpleCov::ArrayFilter.new([proc { false }])).not_to be_matches subject
    end

    it "matches a new SimpleCov::ArrayFilter when a custom class that returns true is passed as array" do
      filter = Class.new(SimpleCov::Filter) do
        def matches?(_)
          true
        end
      end.new(nil)
      expect(SimpleCov::ArrayFilter.new([filter])).to be_matches subject
    end

    it "doesn't match a new SimpleCov::ArrayFilter when a custom class that returns false is passed as array" do
      filter = Class.new(SimpleCov::Filter) do
        def matches?(_)
          false
        end
      end.new(nil)
      expect(SimpleCov::ArrayFilter.new([filter])).not_to be_matches subject
    end

    context "with no filters set up and a basic source file in an array" do
      before do
        @prev_filters = SimpleCov.filters
        SimpleCov.filters = []
      end

      subject do
        [SimpleCov::SourceFile.new(source_fixture("sample.rb"), [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])]
      end

      after do
        SimpleCov.filters = @prev_filters
      end

      it 'returns 0 items after executing SimpleCov.filtered on files when using a "sample" string filter' do
        SimpleCov.add_filter "sample"
        expect(SimpleCov.filtered(subject).count).to be_zero
      end

      it 'returns 0 items after executing SimpleCov.filtered on files when using a "spec/fixtures" string filter' do
        SimpleCov.add_filter "spec/fixtures"
        expect(SimpleCov.filtered(subject).count).to be_zero
      end

      it 'returns 1 item after executing SimpleCov.filtered on files when using a "fooo" string filter' do
        SimpleCov.add_filter "fooo"
        expect(SimpleCov.filtered(subject).count).to eq(1)
      end

      it "returns 0 items after executing SimpleCov.filtered on files when using a block filter that returns true" do
        SimpleCov.add_filter do
          true
        end
        expect(SimpleCov.filtered(subject).count).to be_zero
      end

      it "returns 1 item after executing SimpleCov.filtered on files when using an always-false block filter" do
        SimpleCov.add_filter do
          false
        end
        expect(SimpleCov.filtered(subject).count).to eq(1)
      end

      it "returns a FileList after filtering" do
        SimpleCov.add_filter "fooo"
        expect(SimpleCov.filtered(subject)).to be_a SimpleCov::FileList
      end
    end

    context "with the default configuration" do
      skip "requires the default configuration" if ENV["SIMPLECOV_NO_DEFAULTS"]

      def a_file(path)
        path = File.join(SimpleCov.root, path) unless path.start_with?("/")
        SimpleCov::SourceFile.new(path, [nil, 1, 1, 1, nil, nil, 1, 0, nil, nil])
      end

      context "inside the project" do
        it "doesn't filter" do
          expect(SimpleCov.filtered([a_file("foo.rb")]).count).to eq(1)
        end

        it "filters vendor/bundle" do
          expect(SimpleCov.filtered([a_file("vendor/bundle/foo.rb")]).count).to eq(0)
        end
      end

      context "outside the project" do
        it "filters" do
          expect(SimpleCov.filtered([a_file("/other/path/foo.rb")]).count).to eq(0)
        end

        it "filters even if the sibling directory has SimpleCov.root as a prefix" do
          sibling_dir = SimpleCov.root + "_cache"
          expect(SimpleCov.filtered([a_file(sibling_dir + "/foo.rb")]).count).to eq(0)
        end
      end
    end

    describe ".class_for_argument" do
      it "returns SimpleCov::StringFilter for a string" do
        expect(SimpleCov::Filter.class_for_argument("filestring")).to eq(SimpleCov::StringFilter)
      end

      it "returns SimpleCov::RegexFilter for a string" do
        expect(SimpleCov::Filter.class_for_argument(/regex/)).to eq(SimpleCov::RegexFilter)
      end

      it "returns SimpleCov::RegexFilter for a string" do
        expect(SimpleCov::Filter.class_for_argument(%w[file1 file2])).to eq(SimpleCov::ArrayFilter)
      end
    end
  end
end
