# frozen_string_literal: true

require "helper"
require "simplecov/cli"

RSpec.describe SimpleCov::CLI::JDKRealPath, if: RUBY_ENGINE == "jruby", mutant: false do
  let(:tmp) { File.realpath(Dir.mktmpdir("simplecov-jdk-real-path-")) }
  let(:real_dir) { File.join(tmp, "real").tap { |dir| FileUtils.mkdir_p(dir) } }
  let(:real_file) { File.join(real_dir, "file.rb").tap { |file| File.write(file, "x") } }
  let(:linked_dir) { File.join(tmp, "linked").tap { |link| File.symlink(real_dir, link) } }

  after { FileUtils.remove_entry(tmp) }

  describe ".realpath" do
    it "follows a symlinked file to its target" do
      link = File.join(tmp, "link.rb")
      File.symlink(real_file, link)

      expect(described_class.realpath(link)).to eq(real_file)
    end

    it "follows a symlinked directory partway along the path" do
      real_file

      expect(described_class.realpath(File.join(linked_dir, "file.rb"))).to eq(real_file)
    end

    it "resolves a relative path against the current directory" do
      real_file

      expect(Dir.chdir(real_dir) { described_class.realpath("file.rb") }).to eq(real_file)
    end

    it "raises ENOENT for a path that does not exist" do
      expect { described_class.realpath(File.join(tmp, "gone.rb")) }.to raise_error(Errno::ENOENT)
    end
  end

  describe ".realdirpath" do
    it "resolves an existing file the way realpath does" do
      expect(described_class.realdirpath(File.join(linked_dir, "file.rb").tap { real_file })).to eq(real_file)
    end

    it "resolves the directory of a file that does not exist" do
      expect(described_class.realdirpath(File.join(linked_dir, "gone.rb"))).to eq(File.join(real_dir, "gone.rb"))
    end

    it "raises ENOENT when the directory does not exist either" do
      expect { described_class.realdirpath(File.join(tmp, "nowhere", "gone.rb")) }.to raise_error(Errno::ENOENT)
    end
  end

  it "is the implementation the CLI resolves paths with" do
    expect(SimpleCov::CLI::REAL_PATHS).to be(described_class)
  end
end
