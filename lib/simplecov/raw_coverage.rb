# frozen_string_literal: true

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
    def merge_resultsets(result1, result2)
      (result1.keys | result2.keys).each_with_object({}) do |filename, merged|
        file1 = result1[filename]
        file2 = result2[filename]

        merged[filename] = merge_file_coverage(file1, file2)
      end
    end

    def merge_file_coverage(file1, file2)
      return (file1 || file2).dup unless file1 && file2
      {
        :lines => merge_lines_coverage(file1[:lines], file2[:lines]),
        :branches => merge_branches_coverage(file1[:branches], file2[:branches]) || {},
      }
    end

    def merge_lines_coverage(lines1, lines2)
      return (lines1 || lines2) unless lines1 && lines2

      lines1.map.with_index do |first_coverage_val, index|
        second_coverage_val = lines2[index]
        merge_line_coverage(first_coverage_val, second_coverage_val)
      end
    end

    def merge_line_coverage(count1, count2)
      sum = count1.to_i + count2.to_i
      if sum.zero? && (count1.nil? || count2.nil?)
        nil
      else
        sum
      end
    end

    #
    # Merge branch coverage result by sum the branch access times count.
    # Branches coverage report have same structure for any file
    #
    def merge_branches_coverage(branch1, branch2)
      return (branch1 || branch2) unless branch1 && branch2

      combined_result = branch1.clone

      branch1.each do |(condition, branches_inside)|
        branches_inside.each do |(branch_key, branch_coverage_value)|
          compared_branch_coverage = branch2[condition][branch_key]

          combined_result[condition][branch_key] = branch_coverage_value + compared_branch_coverage
        end
      end

      combined_result
    end
  end
end
