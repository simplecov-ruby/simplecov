require 'yaml'
module SimpleCov::ResultMerger
  class << self
    def resultset_path
      File.join(SimpleCov.coverage_path, 'resultset.yml')
    end
    
    def resultset
      return {} unless File.exist?(resultset_path)
      YAML.load(File.read(resultset_path))
    end
    
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
    
    def merged_result
      merged = {}
      results.each do |result|
        merged = result.original_result.merge_resultset(merged)
      end
      result = SimpleCov::Result.new(merged)
      # Specify the command name
      result.command_name = results.map(&:command_name).join(", ")
      result
    end
    
    def store_result(result)
      new_set = resultset
      command_name, data = result.to_hash.first
      new_set[command_name] = data
      File.open(resultset_path, "w+") do |f|
        f.puts new_set.to_yaml
      end
      true
    end
  end
end