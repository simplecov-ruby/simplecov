module SimpleCov

  class ReportGenerator
    def self.generate_reports(files, report_specifications)
      reports = []
      report_specifications.values.each do |specification|
        case specification[:type]
          when :file_report
            report = SimpleCov::FileReport.new(specification[:options]).generate(files)
          when :author_report
            report = SimpleCov::AuthorReport.new(specification[:options]).generate(files)
        end
        reports << report
      end
      reports
    end

  end # class ReportGenerator

end # module SimpleCov


