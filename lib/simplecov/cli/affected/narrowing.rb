# frozen_string_literal: true

require "open3"
require "tempfile"

module SimpleCov
  module CLI
    module Affected
      # Reads a change to a Ruby file in the recorded source's lines, as two
      # answers. The mask is a bitmap of the recorded lines whose tests the
      # change can affect, in the `ContextMap` encoding: the bodies of the
      # methods it touched. nil means the file cannot be narrowed and every
      # test touching it stays selected: the change reaches outside any method
      # (a constant, a macro, a method added between two), or the recorded
      # source, its base version, or Prism is missing. The load-time lines are
      # the first lines of the statements outside every method that the change
      # rewrote or added to. Those run as the file loads, so a change to them
      # can shape tests that never ran them.
      #
      # The recording's line numbers are the ones that matter, and the
      # recording may predate the change, follow it, or sit anywhere between.
      # A line that differs between the base and the working tree differs from
      # the recording on at least one side, so the change is the union of the
      # base-to-recording and recording-to-working-tree diffs, both read in the
      # recording's coordinates.
      module Narrowing
        HUNK = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

        extend self

        # `base` is the file's source at the merge base, or nil when there is no
        # base to compare (`watch` compares only against the recording). Each
        # edit pairs its side in the recording with its side in the other
        # version. Without Prism every rewritten line counts as load-time.
        def changes(recorded, base, current)
          edits = hunks(base, recorded).map { |old, new| [new, old] } + hunks(recorded, current) #: Array[edit]
          return [nil, edits.flat_map { |edit| rewritten(edit.first) }] unless prism?

          result = Prism.parse(recorded)
          methods = [] #: Array[[Integer, Integer]]
          statements = [] #: Array[[Integer, Integer]]
          collect_spans(result.value, methods, statements)
          silent = silent_lines(recorded, result.comments)
          load_time = edits.flat_map { |edit| load_time_lines(edit, methods, statements, silent) }
          [mask(edits, methods), load_time.uniq]
        end

        def mask(edits, methods)
          edits.reduce(0) do |combined, edit|
            span = innermost(methods, spot(edit.first))
            return nil unless span

            first, last = span
            combined | body_mask(first, last)
          end
        end

        # A rewritten line counts through the innermost statement holding it,
        # unless it is a method's `def` line, whose change the mask covers. An
        # edit that rewrites only blank or comment lines, or none, counts
        # through the statement around it (the file's first when it sits
        # between two at the top), unless it sits in a method or what it brings
        # is nothing that runs or starts with a method.
        def load_time_lines(edit, methods, statements, silent)
          side, other = edit
          lines = rewritten(side) - silent
          return lines.filter_map { |line| statement_start(line, methods, statements) } unless lines.empty?
          return [] if innermost(methods, spot(side)) || !runs_at_load?(other.last)

          [innermost(statements, spot(side)) || statements.first].compact.map(&:first)
        end

        def statement_start(line, methods, statements)
          statement = innermost(statements, [line, line])
          method = innermost(methods, [line, line])
          statement.first if statement && !(method && statement.first <= method.first)
        end

        def rewritten(side)
          first, count, = side
          (first...(first + count)).to_a
        end

        def runs_at_load?(text)
          statement = Prism.parse(text).value.statements.body.first
          !statement.nil? && !statement.instance_of?(Prism::DefNode)
        end

        # Blank lines, and lines holding nothing but a comment.
        def silent_lines(source, comments)
          cuts = comments.to_h { |comment| [comment.location.start_line, comment.location.start_column] }
          lines = source.lines
          (1..lines.size).select do |line|
            text = lines.fetch(line - 1)
            code = text.byteslice(0, cuts.fetch(line, text.bytesize)) #: String
            !/\S/.match?(code)
          end
        end

        # Each hunk as [old side, new side], a side being the first line it
        # covers, how many it covers, and their text.
        def hunks(old_source, new_source)
          return [] unless old_source

          diff(old_source, new_source).scan(HUNK).map do |old_start, old_count, new_start, new_count|
            [side(old_source, old_start, old_count), side(new_source, new_start, new_count)]
          end
        end

        # A hunk of one line omits its count, and one of no lines names the line
        # it follows.
        def side(source, start, count)
          first = Integer(start)
          lines = count ? Integer(count) : 1
          [first, lines, source.lines.slice(first - 1, lines).to_a.join]
        end

        # The lines a side touches. A pure insertion after line k touches the
        # two lines around it, [k, k + 1], which sit in a method exactly when the
        # insertion does.
        def spot(side)
          first, lines, = side
          lines.zero? ? [first, first + 1] : [first, first + lines - 1]
        end

        # The spans around a spot nest, and are collected outermost first, so the
        # last is the innermost.
        def innermost(spans, spot)
          low, high = spot
          spans.reverse.find { |first, last| first <= low && high <= last }
        end

        # The lines a call runs: everything after the `def` line, or the `def`
        # line itself for a method written on one.
        def body_mask(first, last)
          from = first.equal?(last) ? first : first + 1
          ((1 << (last - from + 1)) - 1) << (from - 1)
        end

        # Methods and statements, each collected before the ones nested in it.
        def collect_spans(node, methods, statements)
          methods << [node.start_line, node.end_line] if node.instance_of?(Prism::DefNode)
          statements.concat(node.body.map { |child| [child.start_line, child.end_line] }) if node.instance_of?(Prism::StatementsNode)
          node.compact_child_nodes.each { |child| collect_spans(child, methods, statements) }
        end

        # `git diff --no-index` exits 1 for files that differ, so its status
        # says nothing about failure. Empty output reads as no change.
        #
        # mutant:disable -- for two temporary files outside any repository, read
        # through a pipe, git diffs without an index and without color either
        # way. The flags keep that true when the temporary directory sits in a
        # repository or color is forced on.
        def diff(old_source, new_source)
          Tempfile.create do |old_file|
            Tempfile.create do |new_file|
              old_file.write(old_source)
              new_file.write(new_source)
              [old_file, new_file].each(&:flush)
              Open3.capture2("git", "diff", "--no-index", "--no-color", "-U0", old_file.path, new_file.path).first
            end
          end
        end

        # mutant:disable -- memoized, and a failed load leaves nothing to retry.
        def prism?
          return @prism if defined?(@prism)

          @prism = begin
            require "prism"
            true
          # simplecov:disable — Prism loads wherever the suite runs with coverage
          rescue LoadError
            false
          end
          # simplecov:enable
        end
      end
    end
  end
end
