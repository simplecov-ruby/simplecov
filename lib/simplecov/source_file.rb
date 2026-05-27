# frozen_string_literal: true

require "ripper"
require "set"
require_relative "directive"
require_relative "static_coverage_extractor"

module SimpleCov
  #
  # Representation of a source file including it's coverage data, source code,
  # source lines and featuring helpers to interpret that data.
  #
  class SourceFile
    SHEBANG_REGEX = /\A#!/
    RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX = /\A#\s*(?:-\*-)?\s*(?:en)?coding:\s*(\S+)\s*(?:-\*-)?\s*\z/

    # The full path to this source file (e.g. /User/colszowka/projects/simplecov/lib/simplecov/source_file.rb)
    attr_reader :filename
    # The array of coverage data received from the Coverage.result
    attr_reader :coverage_data

    def initialize(filename, coverage_data, loaded: true)
      @filename = filename
      @coverage_data = coverage_data
      @loaded = loaded
    end

    # The path to this source file relative to the projects directory
    def project_filename
      @filename.delete_prefix(SimpleCov.root).sub(%r{\A[/\\]}, "")
    end

    # The source code for this file. Aliased as :source
    def src
      # We intentionally read source code lazily to
      # suppress reading unused source code.
      @src ||= load_source
    end
    alias source src

    # Returns a hash keyed by every supported coverage criterion. Each
    # value is a CoverageStatistics, even for criteria that weren't
    # enabled during the run — those collapse to 0/0/0. Consumers
    # (FileList, formatters) decide which keys to surface based on
    # `SimpleCov.coverage_criterion_enabled?`. Storing them all keeps
    # the SourceFile contract uniform and lets per-criterion computation
    # remain ignorant of the global enable/disable state.
    def coverage_statistics
      @coverage_statistics ||=
        {
          **line_coverage_statistics,
          **branch_coverage_statistics,
          **method_coverage_statistics
        }
    end

    # Returns all source lines for this file as instances of SimpleCov::SourceFile::Line,
    # and thus including coverage data. Aliased as :source_lines
    def lines
      @lines ||= build_lines
    end
    alias source_lines lines

    # Returns all covered lines as SimpleCov::SourceFile::Line
    def covered_lines
      @covered_lines ||= lines.select(&:covered?)
    end

    # Returns all lines that should have been, but were not covered
    # as instances of SimpleCov::SourceFile::Line
    def missed_lines
      @missed_lines ||= lines.select(&:missed?)
    end

    # Returns all lines that are not relevant for coverage as
    # SimpleCov::SourceFile::Line instances
    def never_lines
      @never_lines ||= lines.select(&:never?)
    end

    # Returns all lines that were skipped as SimpleCov::SourceFile::Line instances
    def skipped_lines
      @skipped_lines ||= lines.select(&:skipped?)
    end

    # Returns the number of relevant lines (covered + missed)
    def lines_of_code
      coverage_statistics[:line]&.total || 0
    end

    # Access SimpleCov::SourceFile::Line source lines by line number
    def line(number)
      lines[number - 1]
    end

    # The coverage for this file in percent. 0 if the file has no coverage lines
    def covered_percent
      coverage_statistics[:line]&.percent
    end

    def covered_strength
      coverage_statistics[:line]&.strength
    end

    def no_lines?
      lines.empty? || (lines.length == never_lines.size)
    end

    def relevant_lines
      lines.size - never_lines.size - skipped_lines.size
    end

    #
    # Return all the branches inside current source file
    def branches
      @branches ||= build_branches
    end

    def no_branches?
      total_branches.empty?
    end

    def branches_coverage_percent
      coverage_statistics[:branch].percent
    end

    #
    # Return the relevant branches to source file
    def total_branches
      @total_branches ||= covered_branches + missed_branches
    end

    #
    # Return hash with key of line number and branch coverage count as value
    def branches_report
      @branches_report ||= build_branches_report
    end

    #
    # Select the covered branches
    # Here we user tree schema because some conditions like case may have additional
    # else that is not in declared inside the code but given by default by coverage report
    #
    # @return [Array]
    #
    def covered_branches
      @covered_branches ||= branches.select(&:covered?)
    end

    #
    # Select the missed branches with coverage equal to zero
    #
    # @return [Array]
    #
    def missed_branches
      @missed_branches ||= branches.select(&:missed?)
    end

    def branches_for_line(line_number)
      branches_report.fetch(line_number, [])
    end

    #
    # Check if any branches missing on given line number
    #
    # @param [Integer] line_number
    #
    # @return [Boolean]
    #
    def line_with_missed_branch?(line_number)
      branches_for_line(line_number).any? { |_type, count| count.zero? }
    end

    # Return all methods detected in this source file
    def methods
      @methods ||= build_methods
    end

    # Return all covered methods
    def covered_methods
      @covered_methods ||= methods.select(&:covered?)
    end

    # Return all missed methods
    def missed_methods
      @missed_methods ||= methods.select(&:missed?)
    end

    def methods_coverage_percent
      coverage_statistics[:method].percent
    end

    # Whether this file was added via track_files but never loaded/required.
    def not_loaded?
      !@loaded
    end

  private

    # no_cov_chunks is zero indexed to work directly with the array holding the lines
    def no_cov_chunks
      @no_cov_chunks ||= build_no_cov_chunks
    end

    def build_no_cov_chunks
      no_cov_lines = src.map.with_index(1).select { |line_src, _index| LinesClassifier.no_cov_line?(line_src) }

      warn_no_cov_deprecation(no_cov_lines.first.last) if no_cov_lines.any?

      # if we have an uneven number of nocovs we assume they go to the
      # end of the file, the source doesn't really matter
      # Can't deal with this within the each_slice due to differing
      # behavior in JRuby: jruby/jruby#6048
      no_cov_lines << ["", src.size] if no_cov_lines.size.odd?

      no_cov_lines.each_slice(2).map do |(_line_src_start, index_start), (_line_src_end, index_end)|
        index_start..index_end
      end
    end

    @nocov_warned = Set.new

    class << self
      attr_reader :nocov_warned
    end

    # Emit a one-time-per-file deprecation warning pointing the user at the
    # `# simplecov:disable` / `# simplecov:enable` replacement.
    def warn_no_cov_deprecation(first_line_number)
      return unless self.class.nocov_warned.add?(filename)

      token = SimpleCov.current_nocov_token
      warn "#{filename}:#{first_line_number}: [DEPRECATION] `# :#{token}:` is deprecated and will be removed " \
           "in a future release. Replace with `# simplecov:disable` / `# simplecov:enable` block comments."
    end

    # Per-category disabled line ranges from `# simplecov:disable` directives.
    def directive_chunks
      @directive_chunks ||= Directive.disabled_ranges(src)
    end

    def load_source
      lines = []
      # The default encoding is UTF-8
      File.open(filename, "rb:UTF-8") do |file|
        current_line = file.gets

        if shebang?(current_line)
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

    def set_encoding_based_on_magic_comment(file, line)
      # Check for encoding magic comment
      # Encoding magic comment must be placed at first line except for shebang
      if (match = RUBY_FILE_ENCODING_MAGIC_COMMENT_REGEX.match(line))
        file.set_encoding(match[1], "UTF-8")
      end
    end

    def ensure_remove_undefs(file_lines)
      # invalid/undef replace are technically not really necessary but nice to
      # have and work around a JRuby incompatibility. Also moved here from
      # simplecov-html to have encoding shenaningans in one place. See #866
      # also setting these option on `file.set_encoding` doesn't seem to work
      # properly so it has to be done here.
      file_lines.each do |line|
        # simplecov:disable — defensive: only fires for non-UTF-8 source files
        line.encode!("UTF-8", invalid: :replace, undef: :replace) unless line.encoding == Encoding::UTF_8
        # simplecov:enable
      end
    end

    def build_lines
      # When `:line` coverage is disabled, the Ruby Coverage module
      # doesn't emit "lines" data, so look up `nil` (never-counted) for
      # every position. The source rows are still useful — e.g. for
      # the HTML report's source view — even without per-line hits.
      line_coverage = coverage_data["lines"] || []
      lines = src.map.with_index(1) do |src, i|
        SimpleCov::SourceFile::Line.new(src, i, line_coverage[i - 1])
      end
      process_skipped_lines(lines)
    end

    def process_skipped_lines(lines)
      mark_chunks_skipped(lines, no_cov_chunks)
      mark_chunks_skipped(lines, directive_chunks.fetch(:line))
      lines
    end

    # The array the lines are kept in is 0-based whereas the line numbers
    # in the chunks are 1-based (more understandable elsewhere), so each
    # range needs to be shifted down by one to slice into `lines`.
    def mark_chunks_skipped(lines, chunks)
      chunks.each { |chunk| lines[(chunk.begin - 1)..(chunk.end - 1)].each(&:skipped!) }
    end

    def lines_strength
      lines.sum { |line| line.coverage.to_i }
    end

    #
    # Build full branches report
    # Root branches represent the wrapper of all condition state that
    # have inside the branches
    #
    # @return [Hash]
    #
    def build_branches_report
      branches.reject(&:skipped?).each_with_object({}) do |branch, coverage_statistics|
        coverage_statistics[branch.report_line] ||= []
        coverage_statistics[branch.report_line] << branch.report
      end
    end

    #
    # Call recursive method that transform our static hash to array of objects
    # @return [Array]
    #
    def build_branches
      coverage_branch_data = coverage_data["branches"] || {}
      branches = coverage_branch_data.flat_map do |condition, coverage_branches|
        next [] if eval_generated_condition_to_ignore?(condition)

        build_branches_from(condition, coverage_branches)
      end

      process_skipped_branches(branches)
    end

    # Detect a Coverage-reported branch condition that originates from
    # `eval`/`module_eval`/`class_eval`/`instance_eval` rather than from
    # the file's literal source. Coverage attributes such branches to the
    # caller's `__FILE__`/`__LINE__`, so a Rails `delegate :foo, to: :bar`
    # call surfaces inside the source file as if there were branches at
    # the `delegate` line. Prism never sees those branches in the static
    # source, so a condition whose start_line isn't in the real-source
    # branch set must be eval-generated. Only consulted when the user has
    # opted in via `SimpleCov.ignore_branches :eval_generated`. See #1046.
    def eval_generated_condition_to_ignore?(condition)
      return false unless SimpleCov.ignored_branch?(:eval_generated)

      positions = real_source_positions
      # simplecov:disable branch — nil branch fires only when Prism is unavailable
      return false unless positions

      # simplecov:enable branch

      _type, _id, start_line, * = restore_ruby_data_structure(condition)
      !positions[:branches].include?(start_line)
    end

    def process_skipped_branches(branches)
      chunks = no_cov_chunks + directive_chunks.fetch(:branch)
      return branches if chunks.empty?

      # A non-inline branch's source range starts on its arm body (e.g. the
      # `:yes` line of `if cond / :yes / else / :no / end`), but `report_line`
      # is the condition line above it — that's where the user sees the
      # branch in the report and where they would naturally place an inline
      # `# simplecov:disable branch` directive. Honour both.
      branches.each do |branch|
        branch.skipped! if chunks.any? { |chunk| branch.overlaps_with?(chunk) || chunk.include?(branch.report_line) }
      end

      branches
    end

    # Since we are dumping to and loading from JSON, and we have arrays as keys those
    # don't make their way back to us intact e.g. just as a string.
    #
    # This safely parses the string representation back to a Ruby array
    # without using eval. See #801.
    #
    def restore_ruby_data_structure(structure)
      # Tests use the real data structures (except for integration tests) so no need to
      # put them through here.
      return structure if structure.is_a?(Array)

      parse_ruby_array_string(structure.to_s)
    end

    # Parse a string like '[:if, 0, 3, 4, 3, 21]' or '["ClassName", :method1, 2, 2, 5, 5]'
    # back into a Ruby array, without using `eval` (see #801). Uses
    # Ripper to walk the literal so we don't need to hand-roll a scanner
    # for symbols, strings, integers, and constant paths.
    def parse_ruby_array_string(str)
      # Try plain Ripper first; only pre-quote `#<...>` inspect segments
      # if the input isn't already valid Ruby (otherwise we corrupt
      # `"#<Class:Foo>"` strings that *are* valid Ruby literals — exactly
      # the shape simplecov-on-simplecov method-coverage keys take).
      sexp = Ripper.sexp(str) || Ripper.sexp(quote_inspected_class_segments(str))
      # simplecov:disable — defensive: Ripper.sexp returning nil from both passes requires malformed input
      array_node = sexp&.dig(1, 0)
      # simplecov:enable
      raise ArgumentError, "expected array literal: #{str.inspect}" unless array_node && array_node[0] == :array

      Array(array_node[1]).map { |element| parse_array_element(element) }
    end

    def parse_array_element(node)
      case node[0]
      when :@int, :unary                 then parse_integer_node(node)
      when :symbol_literal, :dyna_symbol then parse_symbol_node(node)
      when :string_literal               then unescape_ruby(string_literal_text(node[1]))
      when :var_ref                      then node.dig(1, 1) # `Foo`
      when :const_path_ref               then "#{parse_array_element(node[1])}::#{node[2][1]}" # `Foo::Bar`
      else
        # simplecov:disable — defensive fallback for unexpected Ripper node shapes
        raise ArgumentError, "unexpected element: #{node.inspect}"
        # simplecov:enable
      end
    end

    def parse_integer_node(node)
      node[0] == :@int ? node[1].to_i : -node[2][1].to_i
    end

    def parse_symbol_node(node)
      if node[0] == :symbol_literal
        node.dig(1, 1, 1).to_sym
      else
        unescape_ruby(string_literal_text(node[1])).to_sym
      end
    end

    # Concatenate the text fragments of a `:string_content` node. Ripper
    # may emit zero, one, or many `:@tstring_content` children depending
    # on the literal.
    def string_literal_text(string_content)
      Array(string_content[1..]).map { |child| child[1] }.join
    end

    # Undo the same backslash-prefix escapes the previous hand-rolled
    # parser undid: `\X` → `X` for any X.
    def unescape_ruby(raw)
      raw.gsub(/\\(.)/) { ::Regexp.last_match(1) }
    end

    # Method coverage keys can contain inspect-format class references
    # like `#<Class:Foo>` or `#<Class:0x...>`, which aren't valid Ruby
    # syntax. Wrap them in quotes so Ripper can parse the surrounding
    # array literal; downstream we treat them as opaque strings.
    def quote_inspected_class_segments(str)
      str.gsub(/#<[^>]*>/) { |segment| %("#{segment.gsub('"', '\\"')}") }
    end

    def build_branches_from(condition, branches)
      # the format handed in from the coverage data is like this:
      #
      #     [:then, 4, 6, 6, 6, 10]
      #
      # which is [type, id, start_line, start_col, end_line, end_col]
      _condition_type, _condition_id, *condition_range = restore_ruby_data_structure(condition)

      branches.filter_map do |branch_data, hit_count|
        branch_data = restore_ruby_data_structure(branch_data)
        build_branch(branch_data, hit_count, condition_range)
      end
    end

    def build_branch(branch_data, hit_count, condition_range)
      type, _id, start_line, start_col, end_line, end_col = branch_data
      return nil if implicit_else_to_ignore?(type, [start_line, start_col, end_line, end_col], condition_range)

      SourceFile::Branch.new(
        start_line: start_line,
        end_line: end_line,
        coverage: hit_count,
        inline: start_line == condition_range.first,
        type: type
      )
    end

    # Detect synthetic `:else` branches that Ruby's Coverage library reports
    # for constructs with no literal `else` keyword in source (`case/in` /
    # `case/when` without else, `||=`, `&&=`, `if`/`unless` without else,
    # and the postfix `return if cond` shape). The signal is structural:
    # a synthetic else reuses its parent condition's *full source range*
    # (start_line, start_col, end_line, end_col all identical), while an
    # explicit `else` arm carries a narrower range — its own keyword/body
    # position rather than the whole conditional. Comparing the full range
    # (not just `start_line`) is what distinguishes a ternary's explicit
    # else on the same line as the condition — `arg == 42 ? :yes : :no`,
    # where the else's columns differ from the parent's — from a postfix
    # `return if cond` where the synthetic else inherits the full range.
    # Only consulted when the user has opted in via
    # `SimpleCov.ignore_branches :implicit_else`. See #1033.
    def implicit_else_to_ignore?(type, branch_range, condition_range)
      return false unless type == :else
      return false unless SimpleCov.ignored_branch?(:implicit_else)

      branch_range == condition_range
    end

    def line_coverage_statistics
      {
        line: CoverageStatistics.new(
          total_strength: lines_strength,
          covered: covered_lines.size,
          missed: missed_lines.size,
          omitted: never_lines.size
        )
      }
    end

    def branch_coverage_statistics
      # Files added via track_files but never loaded/required have no branch
      # data. Report 0% instead of misleading 100% (see #902).
      if not_loaded? && covered_branches.empty? && missed_branches.empty?
        return {branch: CoverageStatistics.new(covered: 0, missed: 0, percent: 0.0)}
      end

      {
        branch: CoverageStatistics.new(
          covered: covered_branches.size,
          missed: missed_branches.size
        )
      }
    end

    def build_methods
      methods = coverage_data.fetch("methods", {}).filter_map do |info, hit_count|
        info = restore_ruby_data_structure(info)
        next if eval_generated_method_to_ignore?(info)

        SourceFile::Method.new(self, info, hit_count)
      end

      process_skipped_methods(methods)
    end

    # See `eval_generated_condition_to_ignore?` for the rationale. Coverage
    # reports an eval'd `def` at the eval caller's line and name, so a
    # method whose `(name, start_line)` is absent from the real-source
    # `def` set is eval-generated. Only consulted when the user has opted
    # in via `SimpleCov.ignore_methods :eval_generated`. See #1046.
    def eval_generated_method_to_ignore?(info)
      return false unless SimpleCov.ignored_method?(:eval_generated)

      positions = real_source_positions
      # simplecov:disable branch — nil branch fires only when Prism is unavailable
      return false unless positions

      # simplecov:enable branch

      _class_name, name, start_line, * = info
      !positions[:methods].include?([name, start_line])
    end

    # Memoize the Prism-derived set of real source positions (branches at
    # which lines, methods at which (name, line) pairs). Returns nil when
    # Prism is unavailable on this Ruby (older than 3.3 without the gem)
    # or when parsing fails. A nil return makes both eval_generated
    # filters short-circuit to "keep everything" — no false drops when
    # we can't see the static source clearly.
    def real_source_positions
      return @real_source_positions if defined?(@real_source_positions)

      @real_source_positions = StaticCoverageExtractor.real_source_positions(src.join)
    end

    def process_skipped_methods(methods)
      method_chunks = directive_chunks.fetch(:method)
      return methods if method_chunks.empty?

      methods.each do |method|
        method.skipped! if method_chunks.any? { |chunk| method.overlaps_with?(chunk) }
      end

      methods
    end

    def method_coverage_statistics
      if not_loaded? && covered_methods.empty? && missed_methods.empty?
        return {method: CoverageStatistics.new(covered: 0, missed: 0, percent: 0.0)}
      end

      {
        method: CoverageStatistics.new(
          covered: covered_methods.size,
          missed: missed_methods.size
        )
      }
    end
  end
end
