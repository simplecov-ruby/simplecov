# frozen_string_literal: true

require "json"

module SimpleCov
  #
  # Singleton that is responsible for caching, loading and merging
  # SimpleCov::Results into a single result for coverage analysis based
  # upon multiple test suites.
  #
  module ResultMerger
    class << self
      # The path to the .resultset.json cache file
      def resultset_path
        File.join(SimpleCov.coverage_path, ".resultset.json")
      end

      def resultset_writelock
        File.join(SimpleCov.coverage_path, ".resultset.json.lock")
      end

      def merge_and_store(*file_paths, ignore_timeout: false)
        result = merge_results(*file_paths, ignore_timeout: ignore_timeout)
        store_result(result) if result
        result
      end

      def merge_results(*file_paths, ignore_timeout: false)
        # It is intentional here that files are only read in and parsed one at a time.
        #
        # In big CI setups you might deal with 100s of CI jobs and each one producing Megabytes
        # of data. Reading them all in easily produces Gigabytes of memory consumption which
        # we want to avoid.

        file_paths = file_paths.dup
        initial_result = merge_file_results(file_paths.shift, ignore_timeout: ignore_timeout)

        file_paths.reduce(initial_result) do |memo, path|
          file_result = merge_file_results(path, ignore_timeout: ignore_timeout)
          merge_coverage([memo, file_result])
        end
      end

      def merge_file_results(file_path, ignore_timeout:)
        raw_results = parse_file(file_path)
        results = Result.from_hash(raw_results)
        merge_valid_results(results, ignore_timeout: ignore_timeout)
      end

      def parse_file(path)
        data = read_file(path)
        parse_json(data)
      end

      def read_file(path)
        return unless File.exist?(path)

        data = File.read(path)
        return if data.nil? || data.length < 2

        data
      end

      def parse_json(content)
        return {} unless content

        JSON.parse(content) || {}
      rescue StandardError
        warn "[SimpleCov]: Warning! Parsing JSON content of resultset file failed"
        {}
      end

      def merge_valid_results(results, ignore_timeout: false)
        results = results.select { |x| within_merge_timeout?(x) } unless ignore_timeout
        merge_coverage(results)
      end

      def within_merge_timeout?(result)
        Time.now - result.created_at < SimpleCov.merge_timeout
      end

      def merge_coverage(results)
        results = results.compact

        return nil if results.size.zero?
        return results.first if results.size == 1

        parsed_results = results.map(&:original_result)
        combined_result = SimpleCov::Combine::ResultsCombiner.combine(*parsed_results)
        result = SimpleCov::Result.new(combined_result)
        result.command_name = results.map(&:command_name).reject(&:empty?).sort.join(", ")
        result
      end

      #
      # Gets all SimpleCov::Results stored in resultset, merges them and produces a new
      # SimpleCov::Result with merged coverage data and the command_name
      # for the result consisting of a join on all source result's names
      def merged_result
        # conceptually this is just doing `merge_results(resultset_path)`
        # it's more involved to make syre `synchronize_resultset` is only used around reading
        resultset_hash = read_resultset
        results = Result.from_hash(resultset_hash)
        merge_valid_results(results)
      end

      def read_resultset
        resultset_content =
          synchronize_resultset do
            read_file(resultset_path)
          end

        parse_json(resultset_content)
      end

      # Saves the given SimpleCov::Result in the resultset cache
      def store_result(result)
        synchronize_resultset do
          # Ensure we have the latest, in case it was already cached
          new_resultset = read_resultset

          # A single result only ever has one command_name, see `SimpleCov::Result#to_hash`
          command_name, data = result.to_hash.first
          new_resultset[command_name] = data
          File.open(resultset_path, "w+") do |f_|
            f_.puts JSON.pretty_generate(new_resultset)
          end
        end
        true
      end

      # Ensure only one process is reading or writing the resultset at any
      # given time
      def synchronize_resultset
        # make it reentrant
        return yield if defined?(@resultset_locked) && @resultset_locked

        begin
          @resultset_locked = true
          File.open(resultset_writelock, "w+") do |f|
            f.flock(File::LOCK_EX)
            yield
          end
        ensure
          @resultset_locked = false
        end
      end
    end
  end
end
