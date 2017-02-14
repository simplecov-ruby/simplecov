module SimpleCov
  module RawCoverage
    class << self
      # Merges two Coverage.result hashes
      def merge_results(a, b)
        (a.keys | b.keys).each_with_object({}) do |filename, merged|
          result1 = a[filename]
          result2 = b[filename]
          merged[filename] = if result1 && result2
                               merge_arrays(result1, result2)
                             else
                               (result1 || result2).dup
                             end
        end
      end

      private

      def merge_arrays(a, b)
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
end
