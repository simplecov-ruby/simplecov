module SimpleCov
  module RawCoverage
    module_function

    # Merges multiple Coverage.result hashes
    def merge_results(*results)
      results.reduce({}) do |result, merged|
        merge_resultsets(result, merged)
      end
    end

    # Merges two Coverage.result hashes
    def merge_resultsets(a, b)
      (a.keys | b.keys).each_with_object({}) do |filename, merged|
        result1 = a[filename]
        result2 = b[filename]
        merged[filename] = merge_file_coverage(result1, result2)
      end
    end

    def merge_file_coverage(a, b)
      unless a && b
        return (a || b).dup
      end

      a.zip(b).map do |count1, count2|
        sum = count1.to_i + count2.to_i
        if sum.zero? && (count1.nil? || count2.nil?)
          nil
        else
          sum
        end
      end
    end
  end
end
