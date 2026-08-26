# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "error"

module SimpleCov
  module Production
    # The bundled sink: a single JSON file, union-merged under an
    # exclusive lock so any number of processes on the same host can
    # share it. This is the reference for the sink contract:
    #
    #   store(coverage)  # {"lib/foo.rb" => [1, 3, 12], ...} of
    #                    # root-relative paths to sorted line numbers
    #
    # A sink must merge (never replace: many processes each hold only a
    # slice), must be idempotent (the same lines may arrive twice), and
    # signals failure by raising, which makes the runtime keep the
    # delta and retry next interval. Remote sinks — Redis, S3, a
    # metrics pipeline — implement the same one method and live outside
    # this gem.
    #
    # The file's shape, consumed by `simplecov dead-code` and the
    # report formatters:
    #
    #   {"simplecov_production": {
    #     "format_version": 1,
    #     "started_at": "...", "updated_at": "...",
    #     "coverage": {"lib/foo.rb": [1, 3, 12]},
    #     "last_seen": {"lib/foo.rb": "..."}}}
    #
    # `last_seen` stamps each file with the last store that carried it.
    # Oneshot clears on drain, so still-running code re-reports every
    # interval and the stamp tracks real recency, not first sighting.
    # The field is optional on read: a v1 store written before it
    # existed (or by a remote sink that only fills the documented
    # shape) simply has no recency evidence to offer.
    class FileSink
      # The envelope key, which is also how `read` tells a production
      # coverage file from an arbitrary JSON document it must not
      # clobber or misread.
      ENVELOPE = "simplecov_production"
      FORMAT_VERSION = 1

      attr_reader :path

      def initialize(path:)
        @path = File.expand_path(path)
      end

      def store(coverage) # rubocop:disable Naming/PredicateMethod -- the sink contract returns acceptance
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o644) do |file|
          file.flock(File::LOCK_EX)
          existing = self.class.parse(file.read, path)
          rewrite(file, envelope(existing, coverage))
        end
        true
      end

      # Replace the locked file's contents in place, truncating any
      # leftover tail from a previously larger document.
      def rewrite(file, payload)
        file.rewind
        file.write(JSON.generate(payload))
        file.flush
        file.truncate(file.pos)
      end

      # The inner document of a production coverage file:
      # {"format_version" =>, "started_at" =>, "updated_at" =>,
      # "coverage" => {path => [lines]}}. Raises `Error` for anything
      # that is not one, naming the path — misreading an arbitrary JSON
      # file as empty coverage would quietly report every line dead.
      def self.read(path)
        parse(File.read(path), path)
      end

      # @api private — shared by `read` and `store`'s read-modify-write.
      # An empty or missing file is a fresh store.
      def self.parse(content, path)
        return {"coverage" => {}, "last_seen" => {}, "started_at" => nil} if content.strip.empty?

        inner = envelope_of(JSON.parse(content), path)
        inner["coverage"] = {} unless inner["coverage"].is_a?(Hash)
        inner["last_seen"] = {} unless inner["last_seen"].is_a?(Hash)
        inner
      rescue JSON::ParserError => e
        raise Error, "#{path} is not valid JSON (#{e.message.lines.first.to_s.strip})"
      end

      # The document's inner envelope, or the refusal that keeps an
      # arbitrary JSON file from being misread as empty coverage.
      def self.envelope_of(document, path)
        inner = document[ENVELOPE] if document.is_a?(Hash)
        raise Error, "#{path} is not a SimpleCov production coverage file" unless inner.is_a?(Hash)

        inner
      end

    private

      def merge(existing, incoming)
        incoming.each_with_object(existing) do |(file, lines), merged|
          merged[file] = ((merged[file] || []) | lines).sort
        end
      end

      def envelope(existing, incoming)
        now = Time.now.utc.iso8601
        {
          ENVELOPE => {
            "format_version" => FORMAT_VERSION,
            "started_at" => existing["started_at"] || now,
            "updated_at" => now,
            "coverage" => merge(existing["coverage"], incoming).sort.to_h,
            "last_seen" => existing["last_seen"].merge(incoming.keys.to_h { |file| [file, now] }).sort.to_h
          }
        }
      end
    end
  end
end
