module SimpleCov::ArrayMergeHelper
  def merge_resultset(array)
    raise ArgumentError, "Different array lengths" unless array.length == self.length
    new_array = []
    self.each_with_index do |element, i|
      if element.nil? and array[i].nil?
        new_array[i] = nil
      else
        local_value = element || 0
        other_value = array[i] || 0
        new_array[i] = local_value + other_value
      end
    end
    new_array
  end
end

module SimpleCov::HashMergeHelper
  def merge_resultset(hash)
    new_resultset = {}
    self.each do |filename, results|
      new_resultset[filename] = results.merge_resultset(hash[filename])
    end
    new_resultset
  end
end

Array.send :include, SimpleCov::ArrayMergeHelper
Hash.send :include, SimpleCov::HashMergeHelper