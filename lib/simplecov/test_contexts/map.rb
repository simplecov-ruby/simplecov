# frozen_string_literal: true

module SimpleCov
  module TestContexts
    # The serialized, queryable form of a recording: the ordered tests
    # table plus, per file, a bitmap per test (bit `line_number - 1` set
    # = line executed). Standalone so the CLI can load it without
    # booting the singleton.
    class Map
      # `from_hash` treats unknown versions as absent rather than
      # misreading them.
      VERSION = 1

      INDEX_FORMAT = /\A(0|[1-9]\d*)\z/
      MASK_FORMAT = /\A[0-9a-f]+\z/
      private_constant :INDEX_FORMAT, :MASK_FORMAT

      class << self
        # nil when the payload is not the shape and version this writes.
        def from_hash(hash)
          return nil unless hash.is_a?(Hash) && hash["version"] == VERSION

          tests = parse_tests(hash["tests"])
          return nil unless tests

          files = parse_files(hash["files"], tests.size)
          return nil unless files

          new(tests: tests, files: files)
        end

        # A defensive copy of a live accumulator's state (tests table plus
        # per-file masks), letting the accumulator keep growing afterwards.
        def snapshot(table, files)
          copied = {} #: Hash[String, masks]
          files.each { |path, masks| copied[path] = masks.dup }
          new(tests: table.entries.dup, files: copied)
        end

      private

        def parse_tests(raw)
          return nil unless raw.is_a?(Array)

          raw.map do |entry|
            return nil unless entry.is_a?(Array) && entry.size == 2 && entry.all?(String)

            entry #: TestTable::entry
          end
        end

        def parse_files(raw, test_count)
          return nil unless raw.is_a?(Hash)

          files = {} #: Hash[String, masks]
          raw.each do |path, masks|
            parsed = path.is_a?(String) && parse_masks(masks, test_count)
            return nil unless parsed

            files[path] = parsed
          end
          files
        end

        def parse_masks(masks, test_count)
          return nil unless masks.is_a?(Hash)

          masks.to_h do |index, hex|
            pair = parse_mask_pair(index, hex, test_count)
            return nil unless pair

            pair
          end
        end

        def parse_mask_pair(index, hex, test_count)
          return nil unless index.is_a?(String) && index.match?(INDEX_FORMAT)
          return nil unless hex.is_a?(String) && hex.match?(MASK_FORMAT)

          position = Integer(index, 10)
          [position, Integer(hex, 16)] if position < test_count
        end
      end

      attr_reader :tests

      def initialize(tests:, files:)
        @tests = tests
        @files = files
        @sorted_masks = {} #: Hash[String, Array[[Integer, Integer]]]
      end

      def tests_for(filename, line_number)
        masks = @files[filename]
        return [] unless masks && line_number.positive?

        # Range queries ask about the same file once per line; sort once.
        sorted = @sorted_masks[filename] ||= masks.sort
        sorted.filter_map { |index, mask| tests[index] if mask[line_number - 1] == 1 }
      end

      def each_file(&)
        @files.each(&)
      end

      def bitmaps_for(filename)
        empty = {} #: masks
        @files.fetch(filename, empty)
      end

      # Keeps the full tests table so the bitmap indices stay valid.
      def slice(filenames)
        Map.new(tests: tests, files: @files.slice(*filenames))
      end

      # One file's bitmaps in the wire encoding `to_h` writes and
      # `from_hash` reads; coverage.json shares the encoding through this.
      def serialized_bitmaps_for(filename)
        serialize_masks(bitmaps_for(filename))
      end

      def to_h
        files = {} #: Hash[String, Hash[String, String]]
        @files.each do |path, masks|
          serialized = serialize_masks(masks)
          files[path] = serialized unless serialized.empty?
        end
        {"version" => VERSION, "tests" => tests, "files" => files}
      end

    private

      def serialize_masks(masks)
        masks.reject { |_index, mask| mask.zero? }
             .sort.to_h { |index, mask| [index.to_s, mask.to_s(16)] }
      end
    end
  end
end
