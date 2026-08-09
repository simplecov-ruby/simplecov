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
      rename_over(temp.path, path)
    ensure
      temp.close unless temp.closed?
      FileUtils.rm_f(temp.path)
    end
    private_class_method :replace

    # On POSIX systems rename replaces the destination atomically. On
    # Windows it fails with EACCES when the destination is open in a
    # reader or mid-replacement by a concurrent writer, so retry briefly
    # there before giving up.
    def self.rename_over(temp_path, path)
      attempts = 0
      begin
        File.rename(temp_path, path)
      rescue Errno::EACCES
        # simplecov:disable branch — which arm runs is fixed by the platform
        raise unless Gem.win_platform?

        # simplecov:enable branch
        # simplecov:disable — Windows-only; unreachable where dogfood runs
        attempts += 1
        raise if attempts >= 10

        sleep(0.01)
        retry
        # simplecov:enable
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
