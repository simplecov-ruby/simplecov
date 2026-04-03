# frozen_string_literal: true

require "digest/md5"
require "set"
require_relative "coverage_helpers"

module SimpleCov
  module Formatter
    class HTMLFormatter
      # Helper methods used by ERB templates for rendering coverage data.
      module ViewHelpers
        include CoverageHelpers

        def line_status?(source_file, line)
          if branch_coverage? && source_file.line_with_missed_branch?(line.number)
            "missed-branch"
          elsif method_coverage? && missed_method_lines(source_file).include?(line.number)
            "missed-method"
          else
            line.status
          end
        end

        def missed_method_lines(source_file)
          @missed_method_lines ||= {}
          @missed_method_lines[source_file.filename] ||= missed_method_line_set(source_file)
        end

        def missed_method_line_set(source_file)
          source_file.missed_methods
                     .select { |m| m.start_line && m.end_line }
                     .flat_map { |m| (m.start_line..m.end_line).to_a }
                     .to_set
        end

        def coverage_css_class(covered_percent)
          if covered_percent >= 90
            "green"
          elsif covered_percent >= 75
            "yellow"
          else
            "red"
          end
        end

        def id(source_file)
          Digest::MD5.hexdigest(source_file.filename)
        end

        def timeago(time)
          "<abbr class=\"timeago\" title=\"#{time.iso8601}\">#{time.iso8601}</abbr>"
        end

        def shortened_filename(source_file)
          source_file.filename.sub(SimpleCov.root, ".").delete_prefix("./")
        end

        def link_to_source_file(source_file)
          name = shortened_filename(source_file)
          %(<a href="##{id source_file}" class="src_link" title="#{name}">#{name}</a>)
        end

        def covered_percent(percent)
          template("covered_percent").result(binding)
        end

        def to_id(value)
          value.sub(/\A[^a-zA-Z]+/, "").gsub(/[^a-zA-Z0-9\-_]/, "")
        end

        def fmt(number)
          number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
        end
      end
    end
  end
end
