# frozen_string_literal: true

require "fileutils"
require "tempfile"

module SimpleCov
  # Replaces an artifact through a collision-safe temporary file in the
  # destination directory, so readers see either the old or complete new file.
  module AtomicFile
    DEFAULT_MODE = 0o666
    private_constant :DEFAULT_MODE

    def self.write(path, content, binary: false)
      directory = File.dirname(path)
      FileUtils.mkdir_p(directory)
      mode = destination_mode(path)

      Tempfile.create([".simplecov-", ".tmp"], directory) do |temp|
        replace(temp, path, content, mode, binary: binary)
      end

      nil
    end

    def self.replace(temp, path, content, mode, binary:)
      temp.binmode if binary
      temp.write(content)
      temp.close
      File.chmod(mode, temp.path)
      File.rename(temp.path, path)
    ensure
      temp.close unless temp.closed?
      FileUtils.rm_f(temp.path)
    end
    private_class_method :replace

    def self.destination_mode(path)
      return DEFAULT_MODE & ~File.umask if File.symlink?(path)

      File.stat(path).mode & 0o777
    rescue Errno::ENOENT
      DEFAULT_MODE & ~File.umask
    end
    private_class_method :destination_mode
  end
end
