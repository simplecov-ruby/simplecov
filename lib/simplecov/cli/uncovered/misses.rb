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

        def annotate(stdout, files)
          files.each do |fname, _pct, _covered, _total, missed|
            path = fname.delete_prefix("#{File.expand_path(SimpleCov.root)}/")
            Patch::Output.warnings(stdout, path, missed, Patch::Output::ANNOTATIONS.fetch(:line))
          end
        end
      end
    end
  end
end
