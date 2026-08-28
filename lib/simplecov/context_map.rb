# frozen_string_literal: true

module SimpleCov
  #
  # Records which context covered which line: a list of context ids and, per
  # source file, a bitmap of covered lines for each context that touched the
  # file. A context is any labeled region of execution — under `track_tests`
  # every context is one test, identified by its definition site — and the
  # vocabulary is deliberately the general one (coverage.py calls the same
  # idea dynamic contexts), so the stored format doesn't bake simplecov's
  # current use into a name.
  #
  # The naive shape of this data — a list of ids on every line — is
  # O(contexts × lines) strings. Two choices keep it in hand. Context ids
  # are interned, so each id string exists once and everything else refers
  # to it by index (the same problem `Combine::IdentityInterner` solves for
  # the merge combiners' keys). And each context's covered lines within a
  # file are a single Integer bitmap with bit N set when line N+1 was
  # executed, which packs a thousand-line file into ~125 bytes and makes the
  # union of two recordings a bitwise OR.
  #
  # Serialized into `.resultset.json` as `{"version" => 1, "contexts" =>
  # [...ids...], "files" => {path => {context index => bitmap as hex}}}`.
  # The format is tolerated, not trusted: `.from_hash` returns nil for
  # anything malformed or future-versioned (another SimpleCov version, a
  # hand-edited file), which the merge treats the same as a map that was
  # never recorded.
  #
  class ContextMap
    # The serialized format's version. Bumped on any change an older
    # reader could misread, so `.from_hash` can treat a future format as
    # absent instead of answering `covering` queries wrongly from it.
    VERSION = 1

    def initialize
      @contexts = [] #: Array[String]
      @indices = {} #: Hash[String, Integer]
      @files = {} #: Hash[String, Hash[Integer, Integer]]
    end

    # Fold one context's covered lines in. `lines_by_file` maps a source
    # path to the bitmap of lines the context executed there. The id is
    # interned even when the delta is empty: the context ran, and keeping
    # it distinguishes "covered nothing of its own" from "never recorded".
    def record(context_id, lines_by_file)
      index = intern(context_id)
      lines_by_file.each do |path, bitmap|
        next if bitmap.zero?

        table = (@files[path] ||= {})
        table[index] = (table[index] || 0) | bitmap
      end
      self
    end

    # The ids of every recorded context that executed `line` of `path`,
    # sorted for stable output (recording order varies between runs and
    # merges). The path is resolved against `SimpleCov.root`, so callers
    # can pass either an absolute path or a project-relative one, like
    # `Result#source_file_for`.
    def covering(path, line)
      table = @files[File.expand_path(path, SimpleCov.root)]
      return [] unless table

      bit = 1 << (line - 1)
      table.filter_map { |index, bitmap| @contexts.fetch(index) if bitmap.anybits?(bit) }.sort
    end

    # Every recorded context id, in recording order.
    def contexts
      @contexts.dup
    end

    def empty?
      @contexts.empty?
    end

    # Union `other` into this map. Other's contexts are re-interned, so
    # maps recorded by different processes (whose recording order differs)
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

    # The serializable form. `only:` restricts the files to a given set of
    # paths — `Result#to_hash` passes its post-filter filenames, so the map
    # follows the same universe as the coverage it sits beside. The context
    # list is never restricted: which contexts ran is true regardless of
    # which files survived filtering.
    def to_h(only: nil)
      tables = only ? @files.slice(*only.to_a) : @files
      serialized = tables.transform_values { |table| serialize_table(table) }
      {"version" => VERSION, "contexts" => @contexts.dup, "files" => serialized}
    end

    # One file's bitmaps in the wire encoding `to_h` writes — index
    # string => hex bitmap — or an empty table when no recorded context
    # touched the file. coverage.json shares the resultset's encoding
    # through this, so the format has one owner. Paths resolve like
    # `covering`'s.
    def serialized_bitmaps_for(path)
      serialize_table(@files[File.expand_path(path, SimpleCov.root)] || {})
    end

    # @api private — intern `context_id`, returning its stable index.
    def intern(context_id)
      @indices[context_id] ||= begin
        @contexts << context_id
        @contexts.size - 1
      end
    end

    class << self
      # Rebuild a map from its `#to_h` form, or nil when the data is not a
      # well-formed map of this format version. All-or-nothing on purpose:
      # a partially salvaged map would answer `covering` queries with
      # silent gaps, and the merge already has the right treatment for an
      # absent map — drop it consistently rather than keep a wrong one.
      def from_hash(data)
        return nil unless data.is_a?(Hash) && data["version"] == VERSION

        contexts = data["contexts"]
        files = data["files"]
        return nil unless contexts.is_a?(Array) && contexts.all?(String) && files.is_a?(Hash)

        build(contexts, files)
      end

    private

      def build(contexts, files)
        map = new
        contexts.each { |context_id| map.intern(context_id) }
        files.each do |path, table|
          return nil unless path.is_a?(String) && table.is_a?(Hash)
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

      # A serialized context index is a decimal string pointing into the
      # entry's own context list. Anything else — including an
      # out-of-range index — makes the whole map malformed.
      def parse_index(index, size)
        return nil unless index.is_a?(String) && index.match?(/\A\d+\z/)

        value = index.to_i
        value < size ? value : nil
      end

      def parse_bitmap(encoded)
        return nil unless encoded.is_a?(String) && encoded.match?(/\A\h+\z/)

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

    # Raw internals for `absorb`. Protected rather than public because they
    # are live state, not copies.
    def interned_contexts
      @contexts
    end

    def file_tables
      @files
    end
  end
end
