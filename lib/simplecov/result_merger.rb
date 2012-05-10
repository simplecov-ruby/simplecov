require 'multi_json'

#
# Singleton that is responsible for caching, loading and merging
# SimpleCov::Results into a single result for coverage analysis based
# upon multiple test suites.
#
module SimpleCov::ResultMerger
  class << self
    # The path to the resultset.yml cache file
    def resultset_path
      File.join(SimpleCov.coverage_path, '.resultset.json')
    end

    # Loads the cached resultset from YAML and returns it as a Hash
    def resultset
      if stored_data
        # Detect and use available MultiJson API - it changed in v1.3
        if MultiJson.respond_to?(:adapter)
          MultiJson.load(stored_data)
        else
          MultiJson.decode(stored_data)
        end
      else
        {}
      end
    end

    # Returns the contents of the resultset cache as a string or if the file is missing or empty nil
    def stored_data
      if File.exist?(resultset_path) and stored_data = File.read(resultset_path) and stored_data.length >= 2
        stored_data
      else
        nil
      end
    end

    # Gets the resultset hash and re-creates all included instances
    # of SimpleCov::Result from that.
    # All results that are above the SimpleCov.merge_timeout will be
    # dropped. Returns an array of SimpleCov::Result items.
    def results
      results = []
      resultset.each do |command_name, data|
        result = SimpleCov::Result.from_hash(command_name => data)
        # Only add result if the timeout is above the configured threshold
        if (Time.now - result.created_at) < SimpleCov.merge_timeout
          results << result
        end
      end
      results
    end

    #
    # Gets all SimpleCov::Results from cache, merges them and produces a new
    # SimpleCov::Result with merged coverage data and the command_name
    # for the result consisting of a join on all source result's names
    #
    def merged_result
      merged = {}
      results.each do |result|
        merged = result.original_result.merge_resultset(merged)
      end
      result = SimpleCov::Result.new(merged)
      # Specify the command name
      result.command_name = results.map(&:command_name).sort.join(", ")
      result
    end

    # Saves the given SimpleCov::Result in the resultset cache
    def store_result(result)
      new_set = resultset
      command_name, data = result.to_hash.first
      new_set[command_name] = data
      File.open(resultset_path, "w+") do |f|
        if defined? ::JSON
          f.puts JSON.pretty_generate(new_set)
        else
          # Detect and use available MultiJson API - it changed in v1.3
          if MultiJson.respond_to?(:adapter)
            f.puts MultiJson.dump(new_set)
          else
            f.puts MultiJson.encode(new_set)
          end
        end
      end
      true
    end
  end
end
