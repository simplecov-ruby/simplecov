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
          current_line = file.gets

          if current_line && shebang?(current_line)
            lines << current_line
            current_line = file.gets
          end

          read_lines(file, lines, current_line)
        end
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

      # invalid/undef replace are technically not really necessary but
      # nice to have and work around a JRuby incompatibility. Setting
      # these options on `file.set_encoding` doesn't seem to work
      # properly, so it has to be done here.
      def ensure_remove_undefs(file_lines)
        file_lines.each do |line|
          # simplecov:disable — defensive: only fires for non-UTF-8 source files
          line.encode!("UTF-8", invalid: :replace, undef: :replace) unless line.encoding == Encoding::UTF_8
          # simplecov:enable
        end
      end
    end
  end
end
