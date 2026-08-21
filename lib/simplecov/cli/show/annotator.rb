# frozen_string_literal: true

module SimpleCov
  module CLI
    module Show
      # Renders one file's annotated source: a right-aligned line-number
      # gutter, the hit count beside it (blank for never-relevant and
      # nocov lines), and a caret line naming each miss under the line
      # it happened on. Counts and markers colorize under the same rules
      # every other subcommand follows.
      module Annotator
      module_function

        def call(source, entry, stdout, color:)
          markers = markers_for(entry)
          widths = {number: source.size.to_s.length, count: count_width(entry)}
          source.each_with_index do |line, index|
            rendered = row(index + 1, entry["lines"][index], line, widths, color)
            emit(stdout, rendered, markers[index + 1], widths, color)
          end
        end

        def emit(stdout, rendered, labels, widths, color)
          stdout.puts(rendered)
          return if labels.empty?

          gutter = " " * (widths[:number] + widths[:count] + 4)
          stdout.puts(gutter + paint("^ #{labels.join(', ')}", :red, color))
        end

        # The 1-indexed lines the report counts as missed.
        def missed_lines(entry)
          entry["lines"].each_with_index.filter_map do |hit, index|
            index + 1 if hit.is_a?(Integer) && hit.zero?
          end
        end

        # line number => labels, in the order line, branch, method — a
        # line missing more than one way joins them on one caret line.
        def markers_for(entry)
          markers = Hash.new { |hash, line| hash[line] = [] } #: Hash[Integer, Array[String]]
          missed_lines(entry).each { |line| markers[line] << "missed" }
          each_missed(entry["branches"]) { |line| markers[line] << "branch missed" }
          each_missed(entry["methods"]) { |line| markers[line] << "method missed" }
          markers
        end

        # Yields the reported line of each item with a zero hit count.
        def each_missed(items)
          return unless items.is_a?(Array)

          items.each do |item|
            line = missed_line_of(item)
            yield line if line
          end
        end

        # The reported line of a zero-hit item, nil for a covered or
        # malformed one — the same tolerance the patch subcommand
        # applies to branch entries.
        def missed_line_of(item)
          return nil unless item.is_a?(Hash)

          hits = item["coverage"]
          return nil unless hits.is_a?(Integer) && hits.zero?

          line = item["report_line"] || item["start_line"]
          line.is_a?(Integer) ? line : nil
        end

        def count_width(entry)
          entry["lines"].grep(Integer).map { |hit| hit.to_s.length }.max || 1
        end

        # The count is padded to width before it is painted, so escape
        # codes can't skew the column.
        def row(number, hit, line, widths, color)
          count = format("%#{widths[:count]}s", hit.is_a?(Integer) ? hit : "")
          count = paint(count, hit.zero? ? :red : :green, color) if hit.is_a?(Integer)
          format("%#{widths[:number]}d  %s  %s", number, count, line).rstrip
        end

        def paint(text, tint, color)
          SimpleCov::Color.colorize(text, tint, enabled: color)
        end
      end
    end
  end
end
