# frozen_string_literal: true

module SimpleCov
  #
  # Get coverage report on certain file
  #
  module BranchesPerFile
    #
    # @param [String] source_file_path
    #
    # @return [Hash]
    #
    def self.start(source_file_path)
      return {} unless SimpleCov.branchable_report
      Coverage.start(:all)
      require source_file_path
      Coverage.result[source_file_path][:branches]
    end
  end
end
