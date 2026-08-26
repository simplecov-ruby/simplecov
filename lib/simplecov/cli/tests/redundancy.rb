# frozen_string_literal: true

module SimpleCov
  module CLI
    module Tests
      # The `--redundant` sweep: the contexts whose covered lines other
      # contexts also cover, the tests contributing no coverage of their
      # own. A context is non-redundant exactly when some line is covered
      # by it alone, so per file two bitmaps (lines seen once, lines seen
      # more than once) find the uniquely covered lines and a second pass
      # credits each to its owner.
      module Redundancy
      module_function

        # A context with no table entries anywhere covered nothing, which
        # makes it redundant by definition.
        def redundant_ids(document, contexts, opts, stderr)
          tables = sweep_tables(document, contexts, opts, stderr)
          return unless tables

          unique = unique_owners(tables, contexts.size)
          contexts.each_index.reject { |index| unique.fetch(index) }.map { |index| contexts.fetch(index) }.sort
        end

        def unique_owners(tables, context_count)
          unique = Array.new(context_count, false)
          tables.each do |table|
            lone = lone_bits(table)
            table.each { |index, bitmap| unique[index] = true if bitmap.anybits?(lone) }
          end
          unique
        end

        # The bits set in exactly one of the table's bitmaps.
        def lone_bits(table)
          once = 0
          multi = 0
          table.each_value do |bitmap|
            multi |= once & bitmap
            once |= bitmap
          end
          once & ~multi
        end

        # Every file's decoded table. The sweep reads tables no query
        # named, so a malformed one anywhere poisons the whole answer,
        # matching the targeted queries' all-or-nothing tolerance.
        def sweep_tables(document, contexts, opts, stderr)
          coverage = document["coverage"]
          return invalid(opts, stderr, '"coverage" must be an object') unless coverage.is_a?(Hash)

          tables = [] #: Array[Hash[Integer, Integer]]
          coverage.each do |path, entry|
            table = entry.is_a?(Hash) && swept_table(entry, contexts)
            return invalid(opts, stderr, complaint(path, entry)) unless table

            tables << table
          end
          tables
        end

        def swept_table(entry, contexts)
          raw = entry["contexts"] || {}
          raw.is_a?(Hash) ? Tests.decode_table(raw, contexts.size) : nil
        end

        def complaint(path, entry)
          return "entry for #{path} must be an object" unless entry.is_a?(Hash)

          "entry for #{path} carries a malformed \"contexts\" table"
        end

        def invalid(opts, stderr, reason)
          CoverageFile.report_invalid(stderr, "tests", opts[:input], reason)
        end
      end
    end
  end
end
