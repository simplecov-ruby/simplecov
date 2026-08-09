# frozen_string_literal: true

module SimpleCov
  class SourceFile
    # Reads a source file into an array of lines, honoring the source's
    # shebang and `coding:` magic comment when present. Always
    # transcodes to UTF-8 with invalid/undef bytes replaced — both for
    # JRuby compatibility and to keep encoding shenanigans in one place
    # (see #866).
    module SourceLoader
      SHEBANG_REGEX = /\A#!/
      RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX = /\A#\s*(?:-\*-)?\s*(?:en)?coding:\s*(\S+)\s*(?:-\*-)?\s*\z/

    module_function

      def call(filename)
        lines = [] #: Array[String]
        # The default encoding is UTF-8
        File.open(filename, "rb:UTF-8") do |file|
          current_line = scrub_invalid(file.gets)

          if current_line && shebang?(current_line)
            lines << current_line
            current_line = scrub_invalid(file.gets)
          end

          read_lines(file, lines, current_line)
        end
      end

      # A line read as UTF-8 can still carry invalid bytes (a Latin-1
      # source file without a magic comment, say). Replace them before
      # any regex sees the line: the shebang and magic-comment checks
      # would otherwise raise ArgumentError and take the report down.
      def scrub_invalid(line)
        return line if line.nil? || line.valid_encoding?

        line.scrub
      end

      def shebang?(line)
        SHEBANG_REGEX.match?(line)
      end

      def read_lines(file, lines, current_line)
        return lines unless current_line

        set_encoding_based_on_magic_comment(file, current_line)
        lines.concat([current_line], ensure_remove_undefs(file.readlines))
      end

      # Encoding magic comment must be placed at first line except for
      # shebang.
      def set_encoding_based_on_magic_comment(file, line)
        if (match = RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX.match(line))
          file.set_encoding(match[1], "UTF-8")
        end
      end

      # Guarantee every line leaves the loader as valid UTF-8, replacing
      # what can't be represented: transcode non-UTF-8 lines (setting
      # invalid/undef options on `file.set_encoding` doesn't work
      # properly, and this also works around a JRuby incompatibility)
      # and scrub UTF-8-tagged lines that carry invalid bytes, which
      # would otherwise raise from every regex the classifier runs.
      def ensure_remove_undefs(file_lines)
        file_lines.each do |line|
          # simplecov:disable — defensive: only fires for non-UTF-8 source files
          if line.encoding == Encoding::UTF_8
            line.scrub! unless line.valid_encoding?
          else
            line.encode!("UTF-8", invalid: :replace, undef: :replace)
          end
          # simplecov:enable
        end
      end
    end
  end
end
