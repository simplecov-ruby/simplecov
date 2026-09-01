# frozen_string_literal: true

require "helper"
require "simplecov/atomic_file"

RSpec.describe SimpleCov::AtomicFile, mutant_expression: "SimpleCov::AtomicFile*" do
  let(:directory) { Dir.mktmpdir("simplecov-atomic-file-") }
  let(:path) { File.join(directory, "nested", "coverage.json") }

  after { FileUtils.rm_rf(directory) }

  def mode_of(file)
    File.stat(file).mode & 0o777
  end

  def write_existing(content, mode: nil)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(mode, path) if mode
  end

  def with_umask(mask)
    previous = File.umask(mask)
    yield
  ensure
    File.umask(previous)
  end

  it "creates missing parents and writes the exact bytes" do
    content = "{\"source\":\"\xC3\xA9\"}".b
    described_class.write(path, content, binary: true)

    expect(File.binread(path)).to eq(content)
  end

  it "uses normal permissions for a file it creates" do
    control = File.join(directory, "control")
    File.write(control, "control")
    described_class.write(path, "first")
    expect(mode_of(path)).to eq(mode_of(control))
  end

  it "preserves an existing file's restricted permissions" do
    described_class.write(path, "first")
    File.chmod(0o400, path)
    restricted_mode = mode_of(path)
    described_class.write(path, "second")
    expect(mode_of(path)).to eq(restricted_mode)
  end

  it "writes over a file whose permissions are restricted" do
    described_class.write(path, "first")
    File.chmod(0o400, path)
    described_class.write(path, "second")
    expect(File.read(path)).to eq("second")
  end

  it "preserves every permission bit of the file it replaces" do
    write_existing("old", mode: 0o645)
    recorded_mode = mode_of(path)
    described_class.write(path, "new")
    expect(mode_of(path)).to eq(recorded_mode)
  end

  it "honours the umask for a file it creates" do
    skip "the umask is a POSIX concept" if Gem.win_platform?
    with_umask(0o027) { described_class.write(path, "content") }
    expect(mode_of(path)).to eq(0o640)
  end

  it "stages the replacement beside the destination, under a simplecov name" do
    allow(Tempfile).to receive(:create).and_call_original

    described_class.write(path, "content")

    expect(Tempfile).to have_received(:create).with([".simplecov-", ".tmp"], File.dirname(path))
  end

  it "reads a destination's permission bits, without its file type" do
    write_existing("old", mode: 0o645)

    expect(described_class.send(:destination_mode, path)).to eq(mode_of(path))
  end

  it "answers nil, whatever the write produced" do
    expect(described_class.write(path, "content")).to be_nil
  end

  it "flushes the content to disk before the rename" do
    staged = recording_staged_content
    described_class.write(path, "content")
    expect(staged).to eq(["content"])
  end

  def recording_staged_content
    staged = []
    allow(File).to receive(:rename).and_wrap_original do |original, temp, destination|
      staged << File.read(temp.to_path)
      original.call(temp, destination)
    end
    staged
  end

  def recorded_binmodes
    modes = []
    allow(Tempfile).to receive(:create).and_wrap_original do |original, *args, &block|
      original.call(*args) do |temp|
        allow(temp).to(receive(:binmode).and_wrap_original do |binmode|
          modes << :binary
          binmode.call
        end)
        block.call(temp)
      end
    end
    modes
  end

  it "puts the temporary file in binary mode when asked" do
    modes = recorded_binmodes
    described_class.write(path, "a", binary: true)
    expect(modes).to eq([:binary])
  end

  it "leaves the temporary file in text mode when not asked" do
    modes = recorded_binmodes
    described_class.write(path, "b")
    expect(modes).to be_empty
  end

  context "when the rename fails" do
    before do
      allow(Gem).to receive(:win_platform?).and_return(false)
      write_existing("old")
      allow(File).to receive(:rename).and_raise(Errno::EACCES)
    end

    it "raises the error the rename raised" do
      expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
    end

    it "does not retry the rename" do
      suppress(Errno::EACCES) { described_class.write(path, "new") }
      expect(File).to have_received(:rename).once
    end

    it "preserves the old file" do
      suppress(Errno::EACCES) { described_class.write(path, "new") }
      expect(File.read(path)).to eq("old")
    end

    it "removes its temporary file" do
      suppress(Errno::EACCES) { described_class.write(path, "new") }
      expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
    end
  end

  context "when writing the content fails" do
    let(:unwritable) do
      content = Object.new
      allow(content).to receive(:to_s).and_raise(Errno::ENOSPC)
      content
    end

    before { write_existing("old") }

    it "raises the error the write raised" do
      expect { described_class.write(path, unwritable) }.to raise_error(Errno::ENOSPC)
    end

    it "preserves the old file" do
      suppress(Errno::ENOSPC) { described_class.write(path, unwritable) }
      expect(File.read(path)).to eq("old")
    end

    it "closes and removes its temporary file" do
      suppress(Errno::ENOSPC) { described_class.write(path, unwritable) }
      expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
    end
  end

  context "with a symlink at the destination" do
    let(:target) { File.join(directory, "target") }

    before do
      File.write(target, "target")
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(target, path)
    end

    it "replaces the symlink with a file of its own" do
      described_class.write(path, "replacement")
      expect(File).not_to be_symlink(path)
    end

    it "writes the replacement at the destination" do
      described_class.write(path, "replacement")
      expect(File.read(path)).to eq("replacement")
    end

    it "leaves the symlink's target unchanged" do
      described_class.write(path, "replacement")
      expect(File.read(target)).to eq("target")
    end

    it "gives the replacement the umask's mode, not the target's" do
      File.chmod(0o600, target)
      with_umask(0o022) { described_class.write(path, "replacement") }
      expect(mode_of(path)).to eq(0o644)
    end
  end

  context "with concurrent writers" do
    let(:payloads) { Array.new(16) { |index| "#{index}:#{"x" * 100_000}" } }

    before { write_concurrently(payloads) }

    def write_concurrently(payloads)
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
    end

    it "leaves one writer's payload whole at the destination" do
      expect(payloads).to include(File.binread(path))
    end

    it "uses distinct temporary files, leaving no debris behind" do
      expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
    end
  end

  describe "on Windows" do
    before do
      allow(Gem).to receive(:win_platform?).and_return(true)
      allow(described_class).to receive(:sleep)
      write_existing("old")
    end

    def rename_failing_before(attempt)
      calls = 0
      allow(File).to receive(:rename).and_wrap_original do |original, *args|
        calls += 1
        raise Errno::EACCES if calls < attempt

        original.call(*args)
      end
    end

    it "retries a destination another process is holding open" do
      rename_failing_before(3)
      described_class.write(path, "new")
      expect(File.read(path)).to eq("new")
    end

    it "stops retrying as soon as the rename succeeds" do
      rename_failing_before(3)
      described_class.write(path, "new")
      expect(File).to have_received(:rename).exactly(3).times
    end

    context "when the destination stays locked" do
      before { allow(File).to receive(:rename).and_raise(Errno::EACCES) }

      it "raises the lock error in the end" do
        expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
      end

      it "waits between attempts rather than spinning" do
        suppress(Errno::EACCES) { described_class.write(path, "new") }
        expect(described_class).to have_received(:sleep).with(0.01).exactly(9).times
      end

      it "gives up after ten attempts" do
        suppress(Errno::EACCES) { described_class.write(path, "new") }
        expect(File).to have_received(:rename).exactly(10).times
      end

      it "leaves the old file in place" do
        suppress(Errno::EACCES) { described_class.write(path, "new") }
        expect(File.read(path)).to eq("old")
      end

      it "leaves no debris behind" do
        suppress(Errno::EACCES) { described_class.write(path, "new") }
        expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
      end
    end

    context "when the rename fails for something that is not a lock" do
      before { allow(File).to receive(:rename).and_raise(Errno::ENOSPC) }

      it "raises that error" do
        expect { described_class.write(path, "new") }.to raise_error(Errno::ENOSPC)
      end

      it "still gives up immediately" do
        suppress(Errno::ENOSPC) { described_class.write(path, "new") }
        expect(File).to have_received(:rename).once
      end
    end
  end
end
