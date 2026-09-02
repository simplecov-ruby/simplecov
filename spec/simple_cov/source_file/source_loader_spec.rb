# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::SourceFile::SourceLoader do
  let(:tmpdir) { Dir.mktmpdir("simplecov-source-loader-spec-") }

  after { FileUtils.remove_entry(tmpdir) }

  def source_path(content)
    File.join(tmpdir, "source.rb").tap { |path| File.binwrite(path, content) }
  end

  describe ".call" do
    it "reads every line of a plain file" do
      expect(described_class.call(source_path("a = 1\nb = 2\n"))).to eq ["a = 1\n", "b = 2\n"]
    end

    it "reads no lines out of an empty file" do
      expect(described_class.call(source_path(""))).to eq []
    end

    it "keeps a shebang line and everything under it" do
      expect(described_class.call(source_path("#!/usr/bin/env ruby\na = 1\n")))
        .to eq ["#!/usr/bin/env ruby\n", "a = 1\n"]
    end

    it "reads a file that is nothing but a shebang" do
      expect(described_class.call(source_path("#!/usr/bin/env ruby\n"))).to eq ["#!/usr/bin/env ruby\n"]
    end

    it "replaces invalid bytes on the first line, before any regex sees it" do
      expect(described_class.call(source_path("# caf\xE9\na = 1\n"))).to eq ["# caf�\n", "a = 1\n"]
    end

    it "replaces invalid bytes on the lines below the first" do
      expect(described_class.call(source_path("a = 1\nb = 2\n# caf\xE9\n")))
        .to eq ["a = 1\n", "b = 2\n", "# caf�\n"]
    end

    it "reads a file in the encoding its magic comment declares" do
      expect(described_class.call(source_path("# encoding: EUC-JP\n# \xB0\xA1\n")))
        .to eq ["# encoding: EUC-JP\n", "# 亜\n"]
    end

    context "when the default external encoding is not UTF-8" do
      around do |example|
        original = Encoding.default_external
        verbose = $VERBOSE
        $VERBOSE = nil
        Encoding.default_external = Encoding::US_ASCII
        example.run
      ensure
        Encoding.default_external = original
        $VERBOSE = verbose
      end

      it "reads the file as UTF-8 all the same" do
        expect(described_class.call(source_path("# 135°C\n"))).to eq ["# 135°C\n"]
      end
    end

    it "does not run a filename that begins with a pipe" do
      error = Gem.win_platform? ? Errno::EINVAL : Errno::ENOENT
      expect { described_class.call("|echo not-a-file") }.to raise_error(error)
    end
  end

  describe ".scrub_invalid" do
    it "answers nil for nil, which is what an exhausted file hands back" do
      expect(described_class.scrub_invalid(nil)).to be_nil
    end

    it "hands back a valid line untouched" do
      line = +"a = 1\n"

      expect(described_class.scrub_invalid(line)).to be(line)
    end

    it "replaces the invalid bytes of an invalid line" do
      line = (+"# caf\xE9\n").force_encoding(Encoding::UTF_8)

      expect(described_class.scrub_invalid(line)).to eq "# caf�\n"
    end
  end

  describe ".shebang?" do
    it "recognises a shebang at the start of a line" do
      expect(described_class.shebang?("#!/usr/bin/env ruby\n")).to be true
    end

    it "ignores one further along the line" do
      expect(described_class.shebang?("x = 1 #!/usr/bin/env ruby\n")).to be false
    end
  end

  describe ".set_encoding_based_on_magic_comment" do
    it "reads the file in the declared encoding" do
      File.open(source_path("# encoding: EUC-JP\n"), "rb:UTF-8") do |file|
        described_class.set_encoding_based_on_magic_comment(file, "# encoding: EUC-JP\n")

        expect(file.external_encoding).to eq Encoding::EUC_JP
      end
    end

    it "hands the file over as UTF-8" do
      File.open(source_path("# encoding: EUC-JP\n"), "rb:UTF-8") do |file|
        described_class.set_encoding_based_on_magic_comment(file, "# encoding: EUC-JP\n")

        expect(file.internal_encoding).to eq Encoding::UTF_8
      end
    end

    it "leaves the external encoding alone for a line that declares nothing" do
      File.open(source_path("a = 1\n"), "rb:UTF-8") do |file|
        described_class.set_encoding_based_on_magic_comment(file, "a = 1\n")

        expect(file.external_encoding).to eq Encoding::UTF_8
      end
    end

    it "leaves the internal encoding alone for a line that declares nothing" do
      File.open(source_path("a = 1\n"), "rb:UTF-8") do |file|
        described_class.set_encoding_based_on_magic_comment(file, "a = 1\n")

        expect(file.internal_encoding).to be_nil
      end
    end
  end

  describe ".ensure_remove_undefs" do
    it "hands back the very array it was given" do
      lines = [+"a = 1\n"]

      expect(described_class.ensure_remove_undefs(lines)).to be(lines)
    end

    it "leaves a valid UTF-8 line exactly as it was" do
      expect(described_class.ensure_remove_undefs([+"# 135°C\n"])).to eq ["# 135°C\n"]
    end

    it "replaces the invalid bytes of a UTF-8 line in place" do
      line = (+"# caf\xE9\n").force_encoding(Encoding::UTF_8)
      described_class.ensure_remove_undefs([line])

      expect(line).to eq "# caf�\n"
    end

    it "transcodes a line that carries another encoding" do
      line = (+"# \xB0\xA1\n").force_encoding(Encoding::EUC_JP)
      described_class.ensure_remove_undefs([line])

      expect(line).to eq "# 亜\n"
    end

    it "leaves a transcoded line in UTF-8" do
      line = (+"# \xB0\xA1\n").force_encoding(Encoding::EUC_JP)
      described_class.ensure_remove_undefs([line])

      expect(line.encoding).to eq Encoding::UTF_8
    end

    it "replaces bytes that are invalid in the line's own encoding" do
      line = (+"# \x8F\xFF\n").force_encoding(Encoding::EUC_JP)
      described_class.ensure_remove_undefs([line])

      expect(line).to match(/\A# �+\n\z/).and eq("# ��\n") if RUBY_ENGINE == "ruby"
    end

    it "replaces a character its own encoding has and UTF-8 has not" do
      line = (+"# \x8E\xE0\n").force_encoding(Encoding::EUC_JP)
      described_class.ensure_remove_undefs([line])

      expect(line).to eq "# �\n"
    end

    it "leaves a line with an untranslatable character in UTF-8" do
      line = (+"# \x8E\xE0\n").force_encoding(Encoding::EUC_JP)
      described_class.ensure_remove_undefs([line])

      expect(line.encoding).to eq Encoding::UTF_8
    end

    it "replaces bytes that have no UTF-8 meaning at all" do
      line = (+"# caf\xE9\n").force_encoding(Encoding::BINARY)
      described_class.ensure_remove_undefs([line])

      expect(line).to eq "# caf�\n"
    end
  end
end
