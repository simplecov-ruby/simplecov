# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "error"

module SimpleCov
  module Production
    # The bundled sink: a single JSON file, union-merged under an exclusive
    # lock so any number of processes on the same host can share it. This is
    # the reference for the sink contract:
    #
    #   store(coverage)  # {"lib/foo.rb" => [1, 3, 12], ...} of
    #                    # root-relative paths to sorted line numbers
    #
    # A sink must merge (never replace: many processes each hold only a
    # slice), must be idempotent (the same lines may arrive twice), and
    # signals failure by raising, which makes the runtime keep the delta and
    # retry next interval.
    #
    # `last_seen` stamps each file with the last store that carried it.
    # Oneshot clears on drain, so still-running code re-reports every interval
    # and the stamp tracks real recency, not first sighting. The field is
    # optional on read: a v1 store written before it existed simply has no
    # recency evidence to offer.
    class FileSink
      # The envelope key, which is also how `read` tells a production coverage
      # file from an arbitrary JSON document it must not clobber or misread.
      ENVELOPE = "simplecov_production"
      FORMAT_VERSION = 1

      attr_reader :path

      def initialize(path:)
        @path = File.expand_path(path)
      end

      def store(coverage)
        FileUtils.mkdir_p(File.dirname(path))
        with_exclusive_lock do |file|
          existing = self.class.parse(file.read, path)
          rewrite(file, envelope(existing, coverage))
        end
        true
      end

      # Truncates any leftover tail from a previously larger document.
      def rewrite(file, payload)
        file.rewind
        file.write(JSON.generate(payload))
        file.truncate(file.pos)
      end

      # Raises `Error` for anything that is not a production coverage file,
      # naming the path: misreading an arbitrary JSON file as empty coverage
      # would quietly report every line dead.
      def self.read(path)
        parse(File.read(path), path)
      end

      # @api private -- shared by `read` and `store`'s read-modify-write. An
      # empty or missing file is a fresh store. JSON answers plain hashes,
      # arrays, and scalars, never a subclass of one, so the shape checks ask
      # about the class itself.
      def self.parse(content, path)
        return {"coverage" => {}, "last_seen" => {}, "started_at" => nil} if content.match?(/\A\s*\z/)

        inner = envelope_of(JSON.parse(content), path)
        inner["coverage"] = {} unless inner["coverage"].instance_of?(Hash)
        inner["last_seen"] = {} unless inner["last_seen"].instance_of?(Hash)
        inner
      rescue JSON::ParserError => e
        # One line of the parser's complaint, which for some inputs quotes the
        # document back and runs long.
        raise Error, "#{path} is not valid JSON (#{e.message.lines.first.to_s.rstrip})"
      end

      # The refusal is what keeps an arbitrary JSON file from being misread as
      # empty coverage.
      def self.envelope_of(document, path)
        inner = document[ENVELOPE] if document.instance_of?(Hash)
        raise Error, "#{path} is not a SimpleCov production coverage file" unless inner.instance_of?(Hash)

        inner
      end

      private

      # Both halves of the read-modify-write happen through the one handle, so
      # processes sharing the file take turns rather than overwriting each
      # other. The open flags are summed, which for disjoint bits is the same
      # number OR would build and leaves no spelling of the combination
      # without a witness.
      def with_exclusive_lock
        open_file(path, File::RDWR + File::CREAT, 0o644) do |file|
          file.flock(File::LOCK_EX)
          yield file
        end
      end

      # mutant:disable — Ruby 4.0 removed Kernel#open's leading-pipe
      # command mode, so no test can tell `File.open` from `open` here
      # any more. The explicit receiver is kept: on older rubies it is
      # what refuses to run a store path as a command.
      def open_file(name, mode, perm, &)
        File.open(name, mode, perm, &)
      end

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
            "coverage" => merge(existing.fetch("coverage"), incoming).sort.to_h,
            "last_seen" => existing.fetch("last_seen").merge(incoming.transform_values { now }).sort.to_h
          }
        }
      end
    end
  end
end
