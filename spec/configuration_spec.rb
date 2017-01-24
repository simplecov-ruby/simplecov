require "helper"

RSpec.describe SimpleCov::Configuration do
  subject { SimpleCov }

  describe ".coverage_path" do
    let(:coverage_dir) { "/tmp/simplecov/testing/coverage" }

    before(:each) do
      # ensure we're starting from a clean slate
      FileUtils.rmdir(coverage_dir) if File.directory?(coverage_dir)
      @original_coverage_dir = subject.instance_variable_get("@coverage_dir")
      @original_coverage_path = subject.instance_variable_get("@coverage_path")
      subject.instance_variable_set("@coverage_dir", coverage_dir)
      subject.instance_variable_set("@coverage_path", nil)
    end

    after(:each) do
      # so there's no bleed to affect other tests
      subject.instance_variable_set("@coverage_dir", @original_coverage_dir)
      subject.instance_variable_set("@coverage_path", @original_coverage_path)
    end

    it "sets @coverage_path when creating the directory" do
      subject.coverage_path
      expect(subject.instance_variable_get("@coverage_path")).not_to be_nil
    end

    it "memoizes @coverage_path" do
      subject.instance_variable_set("@coverage_path", coverage_dir)
      expect(FileUtils).not_to receive(:mkdir_p)
      subject.coverage_path
    end

    context "when it's a directory" do
      it "creates the directory if it doesn't exist" do
        expect(FileUtils).to receive(:mkdir_p).with(coverage_dir)
        subject.coverage_path
      end

      it "does not create the directory if does exist" do
        FileUtils.mkdir_p(coverage_dir)
        expect(FileUtils).not_to receive(:mkdir_p)
        subject.coverage_path
      end
    end # context "when it's a directory"

    context "when it's a symlink" do
      let(:coverage_link) { "#{coverage_dir}-link" }

      before(:each) do
        FileUtils.rm(coverage_link) if File.symlink?(coverage_link)
        subject.instance_variable_set("@coverage_dir", coverage_link)
      end

      it "creates the directory if it doesn't exist" do
        expect(FileUtils).to receive(:mkdir_p).with(coverage_link)
        subject.coverage_path
      end

      it "does not create the directory if does exist" do
        FileUtils.symlink(coverage_dir, coverage_link)
        expect(FileUtils).not_to receive(:mkdir_p)
        subject.coverage_path
      end
    end # context "when it's a symlink"
  end # describe '.coverage_path'
end
