# frozen_string_literal: true

module SimpleCov
  module CLI
    # The JDK's answer to File.realpath and File.realdirpath, for JRuby. On
    # Windows JRuby's own versions follow no symlinks, and realdirpath accepts
    # a directory that does not exist, so the CLI's containment and identity
    # checks would compare paths that were never resolved. Path#toRealPath has
    # neither problem on any OS. The path is expanded first because the JDK
    # resolves a relative path against the JVM's working directory, which
    # Dir.chdir does not move.
    #
    # simplecov:disable — JRuby-only; this suite's coverage is measured on CRuby
    module JDKRealPath
      extend self

      # mutant:disable — JRuby-only, unreachable from the engine mutant runs on
      def realpath(path)
        expanded = File.expand_path(path)
        java.nio.file.Paths.get(expanded).toRealPath.toString.tr("\\", "/") # steep:ignore NoMethod
      rescue java.nio.file.NoSuchFileException, java.nio.file.NotDirectoryException # steep:ignore NoMethod
        raise Errno::ENOENT, expanded
      rescue java.nio.file.AccessDeniedException # steep:ignore NoMethod
        raise Errno::EACCES, expanded
      rescue java.nio.file.InvalidPathException # steep:ignore NoMethod
        raise Errno::EINVAL, expanded
      end

      # mutant:disable — JRuby-only, unreachable from the engine mutant runs on
      def realdirpath(path)
        expanded = File.expand_path(path)
        return realpath(expanded) if File.exist?(expanded)

        File.join(realpath(File.dirname(expanded)), File.basename(expanded))
      end
    end
    # simplecov:enable

    REAL_PATHS = RUBY_ENGINE.eql?("jruby") ? JDKRealPath : File # simplecov:disable branch — fixed by the running engine
  end
end
