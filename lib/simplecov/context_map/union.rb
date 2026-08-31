# frozen_string_literal: true

module SimpleCov
  class ContextMap
    # Accumulates the context maps of every result a merge absorbs, under the
    # all-or-nothing rule the resultset format needs: the merged result carries
    # the union of the maps when every merged result recorded one, and no map at
    # all otherwise. Keeping a partial union would present one worker's map as
    # the whole run's, silently omitting the tests of the results that didn't
    # record.
    class Union
      attr_reader :carrying, :entries

      def initialize
        @map = ContextMap.new
        @complete = true
        @carrying = 0
        @entries = 0
      end

      def collector
        ->(surviving) { absorb_resultset(surviving) }
      end

      def absorb_resultset(resultset)
        resultset.each_value { |data| absorb_entry(data) }
      end

      def absorb_entry(data)
        @entries += 1
        map = ContextMap.from_hash(data["contexts"])
        return @complete = false unless map

        @carrying += 1
        @map.absorb(map)
      end

      # The parallel merge builds one union per worker over its slice and ships it
      # back, so the parent combines unions rather than re-reading entries.
      def absorb_union(other)
        @entries += other.entries
        @carrying += other.carrying
        @complete &&= other.complete?
        @map.absorb(other.partial_map)
        self
      end

      def complete?
        @complete
      end

      # The union when every absorbed result carried a map, nil otherwise. Dropping
      # warns when the merge mixed results with and without maps, since that
      # usually means `track_tests` is on in some workers and not others; a merge
      # where nothing recorded stays quiet.
      def map
        return @map if @complete

        warn_about_partial_maps
      end

    protected

      # Protected: only another union folding this one in may read it.
      def partial_map
        @map
      end

    private

      def warn_about_partial_maps
        return unless @carrying.positive? && SimpleCov.print_errors

        warn "[SimpleCov]: Dropped the per-test map from the merged result: " \
             "only #{@carrying} of #{@entries} merged results carry one. The map is " \
             "kept only when every merged result records it, so enable `track_tests` " \
             "in every suite that should contribute."
      end
    end
  end
end
