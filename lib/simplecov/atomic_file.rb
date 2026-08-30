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

    # Closing flushes the last buffered bytes, so the rename publishes a
    # complete file rather than whatever happened to reach disk. A closed
    # `File` still stands in for its own path, which is all `chmod` and
    # `rename` want from it.
    #
    # No cleanup of its own: `Tempfile.create` closes and removes the
    # file when its block ends, however the block ends.
    def self.replace(temp, path, content, mode, binary:)
      temp.binmode if binary
      temp.write(content)
      temp.close
      File.chmod(mode, temp)
      rename_over(temp, path)
    end
    private_class_method :replace

    # On POSIX systems rename replaces the destination atomically. On
    # Windows it fails with EACCES when the destination is open in a
    # reader or mid-replacement by a concurrent writer, so retry briefly
    # there before giving up.
    def self.rename_over(temp, path)
      remaining = 10
      begin
        File.rename(temp, path)
      rescue Errno::EACCES
        raise unless Gem.win_platform?

        remaining -= 1
        raise if remaining.zero?

        sleep(0.01)
        retry
      end
    end
    private_class_method :rename_over

    def self.destination_mode(path)
      return DEFAULT_MODE & ~File.umask if File.symlink?(path)

      File.stat(path).mode & 0o777
    rescue Errno::ENOENT
      DEFAULT_MODE & ~File.umask
    end
    private_class_method :destination_mode
  end
end
