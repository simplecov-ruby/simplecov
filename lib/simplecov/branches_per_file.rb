# frozen_string_literal: true

module SimpleCov
  # This module is responsible for generating a branch coverage report for certain file that is missed by the tests.
  # Doing something similar to https://ruby-doc.org/stdlib-2.5.3/libdoc/coverage/rdoc/Coverage.html can throw an error.
  # Errors can be related to Constants, modules are included/extended inside the file but not yet loaded or even exist.
  # It even can be a programmer's error.
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
      coverage_result = Coverage.result

      coverage_result[source_file_path] ? coverage_result[source_file_path][:branches] : {}
    rescue => e
      puts "File with path: #{source_file_path},\n raised '#{e.class}' with message: #{e.message}."
      {}
    end
  end
end
