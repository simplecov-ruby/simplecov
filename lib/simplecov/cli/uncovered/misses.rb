# frozen_string_literal: true

module SimpleCov
  module CLI
    module Uncovered
      module Misses
        extend self

        def missed_for(payload, criterion)
          case criterion
          when :line then payload["lines"].instance_of?(Array) ? Show::Annotator.missed_lines(payload) : []
          when :branch then collect(payload["branches"])
          else collect(payload["methods"])
          end
        end

        def collect(items)
          missed = [] #: Array[Integer]
          Show::Annotator.each_missed(items) { |line| missed << line }
          missed.uniq.sort
        end

        def annotate(stdout, files, criterion, kind)
          root = "#{File.expand_path(SimpleCov.root)}/"
          diagnostics = files.flat_map do |fname, _pct, _covered, _total, missed|
            Annotations.diagnostics(fname.delete_prefix(root), missed, criterion)
          end
          Annotations.emit(stdout, kind, diagnostics)
        end
      end
    end
  end
end
