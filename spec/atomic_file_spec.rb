# frozen_string_literal: true

require "helper"
require "simplecov/atomic_file"

RSpec.describe SimpleCov::AtomicFile do
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
    described_class.write(path, "second")
    expect(File.stat(path).mode & 0o777).to eq(0o400)
    expect(File.read(path)).to eq("second")
  end

  it "preserves the old file and removes its temporary file when rename fails" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "old")
    allow(File).to receive(:rename).and_raise(Errno::EACCES)

    expect { described_class.write(path, "new") }.to raise_error(Errno::EACCES)
    expect(File.read(path)).to eq("old")
    expect(Dir.children(File.dirname(path))).to eq([File.basename(path)])
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
