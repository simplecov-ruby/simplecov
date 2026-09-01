# frozen_string_literal: true

module SimpleCov
  #
  # Records which context covered which line: a list of context ids and, per
  # source file, a bitmap of covered lines for each context that touched the
  # file. A context is any labeled region of execution, and the vocabulary is
  # deliberately the general one (coverage.py calls the same idea dynamic
  # contexts), so the stored format doesn't bake simplecov's current use into
  # a name.
  #
  # The naive shape of this data, a list of ids on every line, is
  # O(contexts x lines) strings. Context ids are interned instead, and each
  # context's covered lines within a file are a single Integer bitmap with bit
  # N set when line N+1 was executed, which packs a thousand-line file into
  # ~125 bytes and makes the union of two recordings a bitwise OR.
  #
  # Serialized into `.resultset.json` as `{"version" => 1, "contexts" =>
  # [...ids...], "files" => {path => {context index => bitmap as hex}}}`. The
  # format is tolerated, not trusted: `.from_hash` returns nil for anything
  # malformed or future-versioned, which the merge treats the same as a map
  # that was never recorded.
  #
  class ContextMap
    # Bumped on any change an older reader could misread, so `.from_hash` can
    # treat a future format as absent instead of answering from it wrongly.
    VERSION = 1

    def initialize
      @contexts = [] #: Array[String]
      @indices = {} #: Hash[String, Integer]
      @files = {} #: Hash[String, Hash[Integer, Integer]]
    end

    # `lines_by_file` maps a source path to the bitmap of lines the context
    # executed there. The id is interned even when the delta is empty: the
    # context ran, and keeping it distinguishes "covered nothing of its own"
    # from "never recorded".
    def record(context_id, lines_by_file)
      index = intern(context_id)
      lines_by_file.each do |path, bitmap|
        next if bitmap.zero?

        table = (@files[path] ||= {})
        table[index] = (table[index] || 0) | bitmap
      end
      self
    end

    # Sorted for stable output, since recording order varies between runs and
    # merges. The path is resolved against `SimpleCov.root`, so callers can
    # pass either an absolute or a project-relative one.
    #
    # A line number below 1 needs no guard of its own: it shifts the probe bit
    # right off the end of the bitmap, leaving a mask no line can match.
    def covering(path, line)
      table = @files[File.expand_path(path, SimpleCov.root)]
      return [] unless table

      bit = 1 << (line - 1)
      table.filter_map { |index, bitmap| @contexts.fetch(index) if bitmap.anybits?(bit) }.sort
    end

    def contexts
      @contexts.dup
    end

    def empty?
      @contexts.empty?
    end

    # Other's contexts are re-interned, so maps recorded by different processes
    # merge by id, and a context both sides saw contributes one entry.
    def absorb(other)
      remap = other.interned_contexts.map { |context_id| intern(context_id) }
      other.file_tables.each do |path, table|
        target = (@files[path] ||= {})
        table.each do |index, bitmap|
          key = remap.fetch(index)
          target[key] = (target[key] || 0) | bitmap
        end
      end
      self
    end

    # `only:` restricts the files to a given set of paths, so the map follows
    # the same universe as the coverage it sits beside. The context list is
    # never restricted: which contexts ran is true regardless of which files
    # survived filtering.
    def to_h(only: nil)
      # Selected rather than sliced: `only` is a Set, and splatting one into
      # `slice` is a call `to_a` answers for, which makes dropping the `to_a` a
      # mutation nothing can observe.
      tables = only ? @files.select { |path, _table| only.include?(path) } : @files # rubocop:disable Style/HashSlice
      serialized = tables.transform_values { |table| serialize_table(table) }
      {"version" => VERSION, "contexts" => @contexts.dup, "files" => serialized}
    end

    # Index string => hex bitmap, the wire encoding `to_h` writes.
    # coverage.json shares the resultset's encoding through this, so the format
    # has one owner.
    def serialized_bitmaps_for(path)
      serialize_table(@files[File.expand_path(path, SimpleCov.root)] || {})
    end

    # @api private
    def intern(context_id)
      @indices[context_id] ||= begin
        @contexts << context_id
        @contexts.size - 1
      end
    end

    class << self
      # nil when the data is not a well-formed map of this format version.
      # All-or-nothing on purpose: a partially salvaged map would answer
      # `covering` queries with silent gaps, and the merge already drops an
      # absent map consistently.
      def from_hash(data)
        # `eql?` rather than `==`: a version written as 1.0 is not this format,
        # and reading it as if it were is what the version gate exists to stop.
        return nil unless data.instance_of?(Hash) && data["version"].eql?(VERSION)

        contexts = data["contexts"]
        files = data["files"]
        return nil unless contexts.instance_of?(Array) && contexts.all?(String) && files.instance_of?(Hash)

        build(contexts, files)
      end

      private

      def build(contexts, files)
        map = new
        contexts.each { |context_id| map.intern(context_id) }
        files.each do |path, table|
          return nil unless path.instance_of?(String) && table.instance_of?(Hash)
          return nil unless absorb_table(map, contexts, path, table)
        end
        map
      end

      def absorb_table(map, contexts, path, table)
        table.all? do |index, encoded|
          position = parse_index(index, contexts.size)
          bitmap = parse_bitmap(encoded)
          map.record(contexts.fetch(position), path => bitmap) if position && bitmap
        end
      end

      # A serialized context index is a decimal string pointing into the entry's
      # own context list. An out-of-range one makes the whole map malformed.
      def parse_index(index, size)
        return nil unless index.instance_of?(String) && index.match?(/\A\d+\z/)

        value = index.to_i
        value if value < size
      end

      def parse_bitmap(encoded)
        return nil unless encoded.instance_of?(String) && encoded.match?(/\A\h+\z/)

        encoded.to_i(16)
      end
    end

    private

    # Sorted by index: recording and merge order vary run to run, and a
    # deterministic serialization keeps stored resultsets diffable.
    def serialize_table(table)
      table.sort.to_h { |index, bitmap| [index.to_s, bitmap.to_s(16)] }
    end

    protected

    # Live state, not copies, which is why these are protected rather than
    # public.
    def interned_contexts
      @contexts
    end

    def file_tables
      @files
    end
  end
end
