# frozen_string_literal: true

require "helper"
require "simplecov/atomic_file"

RSpec.describe SimpleCov::AtomicFile, mutant_expression: "SimpleCov::AtomicFile*" do
  let(:directory) { Dir.mktmpdir("simplecov-atomic-file-") }
  let(:path) { File.join(directory, "nested", "coverage.json") }

  after { FileUtils.rm_rf(directory) }

  it "creates missing parents and writes the exact bytes" do
    content = "{\"source\":\"\xC3\xA9\"}".b
    described_class.write(path, content, binary: true)

    expect(File.binread(path)).to eq(content)
  end

  it "uses normal permissions for new files and preserves existing permissions" do
    control = File.join(directory, "control")
    File.write(control, "control")
    described_class.write(path, "first")
    expect(File.stat(path).mode & 0o777).to eq(File.stat(control).mode & 0o777)

    File.chmod(0o400, path)
    restricted_mode = File.stat(path).mode & 0o777
    described_class.write(path, "second")
    expect(File.stat(path).mode & 0o777).to eq(restricted_mode)
    expect(File.read(path)).to eq("second")
  end

  it "preserves the old file and removes its temporary file when rename fails" do
    allow(Gem).to receive(:win_platform?).and_return(false)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "old")
    allow(File).to receive(:rename).and_raise(Errno::EACCES)

    expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
    expect(File).to have_received(:rename).once
    expect(File.read(path)).to eq("old")
    expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
  end

  it "preserves every permission bit of the file it replaces" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "old")
    File.chmod(0o645, path)
    recorded_mode = File.stat(path).mode & 0o777

    described_class.write(path, "new")

    expect(File.stat(path).mode & 0o777).to eq(recorded_mode)
  end

  it "closes and removes its temporary file when writing fails" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "old")
    content = Object.new
    allow(content).to receive(:to_s).and_raise(Errno::ENOSPC)

    expect { described_class.write(path, content) }.to raise_error(Errno::ENOSPC)
    expect(File.read(path)).to eq("old")
    expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
  end

  it "replaces a destination symlink without changing its target" do
    target = File.join(directory, "target")
    File.write(target, "target")
    FileUtils.mkdir_p(File.dirname(path))
    File.symlink(target, path)

    described_class.write(path, "replacement")

    expect(File).not_to be_symlink(path)
    expect(File.read(path)).to eq("replacement")
    expect(File.read(target)).to eq("target")
  end

  describe "on Windows" do
    before do
      allow(Gem).to receive(:win_platform?).and_return(true)
      allow(described_class).to receive(:sleep)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "old")
    end

    it "retries a destination another process is holding open" do
      calls = 0
      allow(File).to receive(:rename).and_wrap_original do |original, *args|
        calls += 1
        raise Errno::EACCES if calls < 3

        original.call(*args)
      end

      described_class.write(path, "new")

      expect(File.read(path)).to eq("new")
      expect(calls).to eq(3)
    end

    it "waits between attempts rather than spinning" do
      allow(File).to receive(:rename).and_raise(Errno::EACCES)

      expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
      expect(described_class).to have_received(:sleep).with(0.01).exactly(9).times
    end

    it "gives up after ten attempts, leaving the old file and no debris" do
      allow(File).to receive(:rename).and_raise(Errno::EACCES)

      expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
      expect(File).to have_received(:rename).exactly(10).times
      expect(File.read(path)).to eq("old")
      expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
    end

    it "still gives up immediately on an error that is not a lock" do
      allow(File).to receive(:rename).and_raise(Errno::ENOSPC)

      expect { described_class.write(path, "new") }.to raise_error(Errno::ENOSPC)
      expect(File).to have_received(:rename).once
    end
  end

  it "honours the umask for a file it creates" do
    skip "the umask is a POSIX concept" if Gem.win_platform?

    previous = File.umask(0o027)
    described_class.write(path, "content")
    expect(File.stat(path).mode & 0o777).to eq(0o640)
  ensure
    File.umask(previous)
  end

  it "gives a replaced symlink the umask's mode, not the target's" do
    target = File.join(directory, "target")
    File.write(target, "target")
    File.chmod(0o600, target)
    FileUtils.mkdir_p(File.dirname(path))
    File.symlink(target, path)

    previous = File.umask(0o022)
    described_class.write(path, "replacement")
    expect(File.stat(path).mode & 0o777).to eq(0o644)
  ensure
    File.umask(previous)
  end

  it "stages the replacement beside the destination, under a simplecov name" do
    allow(Tempfile).to receive(:create).and_call_original

    described_class.write(path, "content")

    expect(Tempfile).to have_received(:create).with([".simplecov-", ".tmp"], File.dirname(path))
  end

  it "reads a destination's permission bits, without its file type" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "old")
    File.chmod(0o645, path)

    expect(described_class.send(:destination_mode, path)).to eq(File.stat(path).mode & 0o777)
  end

  it "puts the temporary file in binary mode only when asked" do
    modes = []
    allow(Tempfile).to receive(:create).and_wrap_original do |original, *args, &block|
      original.call(*args) do |temp|
        allow(temp).to(receive(:binmode).and_wrap_original do |m|
          modes << :binary
          m.call
        end)
        block.call(temp)
      end
    end

    described_class.write(path, "a", binary: true)
    expect(modes).to eq([:binary])

    described_class.write(path, "b")
    expect(modes).to eq([:binary])
  end

  it "flushes the content to disk before the rename" do
    staged = nil
    allow(File).to receive(:rename).and_wrap_original do |original, temp, destination|
      staged = File.read(temp.to_path)
      original.call(temp, destination)
    end

    described_class.write(path, "content")

    expect(staged).to eq("content")
  end

  it "answers nil, whatever the write produced" do
    expect(described_class.write(path, "content")).to be_nil
  end

  it "uses distinct temporary files for concurrent writers" do
    payloads = Array.new(16) { |index| "#{index}:#{'x' * 100_000}" }
    ready = Queue.new
    start = Queue.new
    threads = payloads.map do |payload|
      Thread.new do
        ready << true
        start.pop
        described_class.write(path, payload)
      end
    end
    threads.size.times { ready.pop }
    threads.size.times { start << true }
    threads.each(&:value)

    expect(payloads).to include(File.binread(path))
    expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
  end
end
