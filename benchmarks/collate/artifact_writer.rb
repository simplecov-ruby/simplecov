# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "shape"

module CollateBenchmark
  # Writes the two artifacts a collate needs on disk: the source tree the
  # report phase reads, and the resultset shards the merge phase folds.
  class ArtifactWriter
    def initialize(files:, project_dir:, result_files_dir:, seed:, progress:)
      @files = files
      @project_dir = project_dir
      @result_files_dir = result_files_dir
      @rng = Random.new(seed)
      @progress = progress
    end

    # The report phase reads every file in the result, so the tree has to exist
    # with matching line counts. Content only has to classify the same way the
    # coverage data does and be of realistic width.
    def write_sources
      made = {}
      @files.each_with_index do |file, index|
        path = File.join(@project_dir, file.relative_path)
        directory = File.dirname(path)
        made[directory] ||= FileUtils.mkdir_p(directory) && true
        File.write(path, source_body(file.lines))
        @progress.call(index + 1, @files.size, "source files")
      end
    end

    # Shards differ only in hit counts, so the structure is mutated in place,
    # written, and reverted — no per-shard copy of six figures' worth of line
    # entries.
    def write_resultsets(count)
      # One timestamp for the whole set: shards of a real run land seconds
      # apart, and a single value keeps every shard's byte length identical.
      timestamp = Time.now.to_i
      count.times do |index|
        drift = apply_drift
        File.write(shard_path(index), resultset_json(timestamp))
        revert_drift(drift)
        @progress.call(index + 1, count, "resultsets")
      end
    end

  private

    def shard_path(index)
      File.join(@result_files_dir, ".resultset-#{index}.json")
    end

    def source_body(lines)
      lines.each_with_index.map do |hits, index|
        if hits.nil?
          "    # notes on why line #{index + 1} behaves the way it does"
        else
          "    value_#{index} = compute(record_#{index}, key: :option_#{index % 7})"
        end
      end.join("\n") << "\n"
    end

    def resultset_json(timestamp)
      coverage = @files.to_h do |file|
        [File.join(@project_dir, file.relative_path),
         {"lines" => file.lines, "branches" => file.branches}]
      end
      # `JSON.pretty_generate` is what SimpleCov itself writes, and the
      # resulting file width is a real input to the parse phase.
      JSON.pretty_generate("RSpec" => {"coverage" => coverage, "timestamp" => timestamp})
    end

    # Returns undo records so the shared structure can be restored.
    def apply_drift
      drift_count.times.filter_map { drift_one_line }
    end

    def drift_count
      total = @files.sum { |file| file.lines.size }
      (total * Shape::SHARD_DRIFT_FRACTION).round
    end

    def drift_one_line
      lines = @files[@rng.rand(@files.size)].lines
      index = @rng.rand(lines.size)
      previous = lines[index]
      return nil if previous.nil?

      lines[index] = previous.zero? ? @rng.rand(1..3) : previous + @rng.rand(1..4)
      [lines, index, previous]
    end

    def revert_drift(drift)
      drift.each { |lines, index, previous| lines[index] = previous }
    end
  end
end
