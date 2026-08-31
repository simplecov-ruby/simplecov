# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Reads a source file into an array of lines, honoring the source's shebang
    # and `coding:` magic comment when present. Always transcodes to UTF-8 with
    # invalid and undefined bytes replaced, both for JRuby compatibility and to
    # keep encoding shenanigans in one place (#866).
    module SourceLoader
      SHEBANG_REGEX = /\A#!/
      RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX = /\A#\s*(?:-\*-)?\s*(?:en)?coding:\s*(\S+)\s*(?:-\*-)?\s*\z/

      extend self

      def call(filename)
        lines = [] #: Array[String]
        open_file(filename, "rb:UTF-8") do |file|
          read_lines(file, lines, scrub_invalid(file.gets))
        end
      end

      # mutant:disable — Ruby 4.0 removed Kernel#open's leading-pipe
      # command mode, so no test can tell `File.open` from `open` here
      # any more. The explicit receiver is kept: on older rubies it is
      # what refuses to run a filename as a command.
      def open_file(name, mode, &)
        File.open(name, mode, &)
      end

      # A line read as UTF-8 can still carry invalid bytes, from a Latin-1 source
      # file without a magic comment, say. They are replaced before any regex sees
      # the line: the shebang and magic-comment checks would otherwise raise
      # ArgumentError and take the report down.
      def scrub_invalid(line)
        return line if line.nil? || line.valid_encoding?

        line.scrub
      end

      def shebang?(line)
        SHEBANG_REGEX.match?(line)
      end

      def read_lines(file, lines, current_line)
        return lines unless current_line

        if shebang?(current_line)
          lines << current_line
          current_line = scrub_invalid(file.gets)
          return lines unless current_line
        end

        set_encoding_based_on_magic_comment(file, current_line)
        lines.concat([current_line], ensure_remove_undefs(file.readlines))
      end

      # An encoding magic comment must be placed on the first line, except after a
      # shebang.
      def set_encoding_based_on_magic_comment(file, line)
        if (match = RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX.match(line))
          file.set_encoding(match[1], "UTF-8")
        end
      end

      # Setting invalid/undef options on `file.set_encoding` doesn't work
      # properly, and transcoding here also works around a JRuby incompatibility.
      def ensure_remove_undefs(file_lines)
        file_lines.each { |line| make_utf8(line) }
      end

      # mutant:disable — on CRuby the two arms answer alike, because
      # converting to the encoding a string already carries scrubs it
      # when `invalid: :replace` is given. The arms are kept apart for
      # the engines where that conversion is the documented no-op it
      # reads as, which is the same reason the transcode is here rather
      # than on `file.set_encoding`.
      # Encodings are singletons, so identity is the whole of the question. A line
      # already tagged UTF-8 has nothing to transcode, only invalid bytes to
      # replace, and scrubbing a line that has none of those leaves it alone.
      def make_utf8(line)
        if line.encoding.equal?(Encoding::UTF_8)
          line.scrub!
        else
          line.encode!("UTF-8", invalid: :replace, undef: :replace)
        end
      end
    end
  end
end
