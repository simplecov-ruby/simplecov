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

        # GitHub workflow commands, one ::warning per contiguous missed range, so a
        # plain workflow gets inline diff annotations with no upload step and no
        # code-scanning permissions.
        def annotate(stdout, files)
          files.each do |fname, _pct, _covered, _total, missed|
            path = fname.delete_prefix("#{File.expand_path(SimpleCov.root)}/")
            missed.slice_when { |previous, current| current > previous + 1 }.each do |run|
              stdout.puts("::warning file=#{path},line=#{run.first},endLine=#{run.last}::Not covered by tests")
            end
          end
        end
      end
    end
  end
end
