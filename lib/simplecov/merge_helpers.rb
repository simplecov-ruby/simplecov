module SimpleCov
  module ArrayMergeHelper
    # Merges an array of coverage results with self
    def merge_resultset(array)
      each_with_index.map do |element, i|
        if element.nil? || array[i].nil?
          nil
        else
          element + array[i]
        end
      end
    end
  end
end

module SimpleCov
  module HashMergeHelper
    # Merges the given Coverage.result hash with self
    def merge_resultset(hash)
      new_resultset = {}
      (keys + hash.keys).each do |filename|
        if self[filename].nil?
          new_resultset[filename] = hash[filename]
        elsif hash[filename].nil?
          new_resultset[filename] = self[filename]
        else
          new_resultset[filename] = self[filename].merge_resultset(hash[filename])
        end
      end
      new_resultset
    end
  end
end

Array.send :include, SimpleCov::ArrayMergeHelper
Hash.send :include, SimpleCov::HashMergeHelper
