# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "artifact_writer"
require_relative "file_structure"
require_relative "shape"

module CollateBenchmark
  module Fixture
    extend self

    GENERATOR_VERSION = 1
    SEED = 20_240_517

    DIR = File.expand_path("../../tmp/collate-benchmark", __dir__)
    RESULT_FILES_DIR = File.join(DIR, "result_files")
    PROJECT_DIR = File.join(DIR, "project")
    COVERAGE_DIR = File.join(DIR, "coverage")
    TIMINGS_DIR = File.join(DIR, "timings")
    MANIFEST_PATH = File.join(DIR, "manifest.json")

    Built = Struct.new(:root, :resultset_paths, :file_count, :line_count, :condition_count)

    def dir
      DIR
    end

    def prepare(scale:, resultsets:, force: false)
      build(scale, resultsets) if force || !cached?(scale, resultsets)
      built(resultsets)
    end

    def cached?(scale, resultsets)
      manifest = manifest_on_disk
      return false unless manifest

      manifest.values_at("generator_version", "seed", "scale") == [GENERATOR_VERSION, SEED, scale] &&
        manifest["resultsets"].to_i >= resultsets
    end

    def manifest_on_disk
      return nil unless File.exist?(MANIFEST_PATH)

      JSON.parse(File.read(MANIFEST_PATH))
    rescue JSON::ParserError
      nil
    end

    def built(resultsets)
      manifest = manifest_on_disk
      Built.new(
        root: PROJECT_DIR,
        resultset_paths: resultset_paths.first(resultsets),
        file_count: manifest["files"],
        line_count: manifest["lines"],
        condition_count: manifest["conditions"]
      )
    end

    def resultset_paths
      Dir.glob(File.join(RESULT_FILES_DIR, ".resultset-*.json"))
        .sort_by { |path| path[/-(\d+)\.json\z/, 1].to_i }
    end

    def build(scale, resultsets)
      FileUtils.rm_rf(DIR)
      FileUtils.mkdir_p([RESULT_FILES_DIR, PROJECT_DIR])

      files = FileStructure.new(scale: scale, seed: SEED).call
      write_artifacts(files, resultsets)
      write_manifest(files, scale, resultsets)
    end

    def write_artifacts(files, resultsets)
      writer = ArtifactWriter.new(
        files: files, project_dir: PROJECT_DIR, result_files_dir: RESULT_FILES_DIR,
        seed: SEED + 1, progress: method(:progress)
      )
      writer.write_sources
      writer.write_resultsets(resultsets)
    end

    def write_manifest(files, scale, resultsets)
      manifest = {
        "generator_version" => GENERATOR_VERSION, "seed" => SEED,
        "scale" => scale, "resultsets" => resultsets,
        "files" => files.size,
        "lines" => files.sum { |file| file.lines.size },
        "conditions" => files.sum { |file| file.branches.size }
      }
      File.write(MANIFEST_PATH, JSON.pretty_generate(manifest))
    end

    def progress(done, total, label)
      if $stderr.tty?
        return unless done == total || (done % 25).zero?

        $stderr.print("\r[fixture] #{label}: #{done}/#{total}")
        $stderr.puts if done == total
      elsif done == total
        warn("[fixture] #{label}: #{total}")
      end
    end
  end
end
