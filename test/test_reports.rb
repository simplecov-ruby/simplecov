require 'helper'

module SimpleCov
  class SourceFile
    class Line
      attr_accessor :author
    end
  end

  SimpleCov::SourceFile.add_line_enhancer(lambda do |lines, filename|
      lines.each { |line| line.author = "bob" }
    end
  )

  class CoolReport < Report
    def initialize(options)
    end

    def generate(files)
      @report = {
        :type => {
          :main => :cool_report
        }
      }
    end
  end

  SimpleCov::Report.register(:cool_report, SimpleCov::CoolReport)

  module Configuration
    module ReportTypes
      module CoolReport
        def self.get_specification(options)
          {
            :type => :cool_report,
            :options => {}
          }
        end
      end
    end
  end
end

def start_simplecov
  SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter

  SimpleCov.start do
    use_merging true
    merge_timeout 3600
    command_name "Test"
    add_report :type => SimpleCov::Configuration::ReportTypes::CoolReport
  end
end



class TestReports < Test::Unit::TestCase
  context "Coverage data generated with reports configured" do
    setup do
      start_simplecov
      require_relative "fixtures/report_targets/Animal"
      Animal.new.cry
      @result = SimpleCov.result.format!
    end

    should "generate reports data" do
      assert_equal @result, "Reports:\n\nReport: {:main=>:cool_report}\n{:type=>{:main=>:cool_report}}\n\n",
                   "coverage report doesn't match expectations"
    end

    should "generate coverage for all the files" do
      expected_files = [
        File.expand_path(File.join(File.dirname(__FILE__), "fixtures/report_targets/Animal.rb"))
      ]
      observed_files = []
      SimpleCov.result.files.each do |file|
        observed_files << file.filename
      end
      assert_equal expected_files, observed_files, "Files covered is not as expected"
    end

    should "generate coverage for all the files" do
      SimpleCov.result.files.each do |file|
        file.lines.each do |line|
          assert_equal line.author, "bob", "enhanced line attributes aren't there"
        end
      end
    end
  end
end

