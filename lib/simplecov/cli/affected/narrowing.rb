# frozen_string_literal: true

require "open3"
require "tempfile"

module SimpleCov
  module CLI
    module Affected
      # Narrows a changed Ruby file to the methods the change touched, as a
      # bitmap of the recorded lines whose tests the change can affect, in the
      # `ContextMap` encoding. nil means the file cannot be narrowed and every
      # test touching it stays selected: the change reaches outside any method
      # (a constant, a macro, a method added between two), or the recorded
      # source, its base version, or Prism is missing.
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
        # base to compare (`watch` compares only against the recording).
        def mask(recorded, base, current)
          return unless prism?

          spots = changed_spots(base, recorded).map(&:last) + changed_spots(recorded, current).map(&:first)
          methods = method_spans(recorded)
          spots.reduce(0) do |combined, spot|
            span = innermost(methods, spot)
            return nil unless span

            first, last = span
            combined | body_mask(first, last)
          end
        end

        def rewritten_lines(recorded, base, current)
          return unless prism?

          lines = hunk_lines(base, recorded).flat_map(&:last) + hunk_lines(recorded, current).flat_map(&:first)
          def_lines = method_spans(recorded).map(&:first)
          lines - def_lines
        end

        def hunk_lines(old_source, new_source)
          return [] unless old_source

          diff(old_source, new_source).scan(HUNK).map do |old_start, old_count, new_start, new_count|
            [line_numbers(old_start, old_count), line_numbers(new_start, new_count)]
          end
        end

        def line_numbers(start, count)
          first = Integer(start)
          (first...(first + (count ? Integer(count) : 1))).to_a
        end

        # Each hunk as [old spot, new spot], a spot being the [first, last] lines
        # it covers on that side. A pure insertion after line k touches the two
        # lines around it, [k, k + 1], which sit in a method exactly when the
        # insertion does.
        def changed_spots(old_source, new_source)
          return [] unless old_source

          diff(old_source, new_source).scan(HUNK).map do |old_start, old_count, new_start, new_count|
            [spot(old_start, old_count), spot(new_start, new_count)]
          end
        end

        # A hunk of one line omits its count, and one of no lines names the line
        # it follows.
        def spot(start, count)
          first = Integer(start)
          lines = count ? Integer(count) : 1
          lines.zero? ? [first, first + 1] : [first, first + lines - 1]
        end

        # The methods around a spot nest, and are collected outermost first, so
        # the last is the innermost.
        def innermost(methods, spot)
          low, high = spot
          methods.reverse.find { |first, last| first <= low && high <= last }
        end

        # The lines a call runs: everything after the `def` line, or the `def`
        # line itself for a method written on one.
        def body_mask(first, last)
          from = first.equal?(last) ? first : first + 1
          ((1 << (last - from + 1)) - 1) << (from - 1)
        end

        def method_spans(source)
          spans = [] #: Array[[Integer, Integer]]
          collect_spans(Prism.parse(source).value, spans)
          spans
        end

        def collect_spans(node, spans)
          spans << [node.start_line, node.end_line] if node.instance_of?(Prism::DefNode)
          node.compact_child_nodes.each { |child| collect_spans(child, spans) }
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
