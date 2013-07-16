module SimpleCov

  class ReportGenerator
    def self.generate_reports(files, report_specifications)
      reports = []
      report_specifications.values.each do |specification|
        report_type = Report.report_types[specification[:type]]
        report = report_type.new(specification[:options]).generate(files)
        reports << report
      end
      reports
    end

  end # class ReportGenerator

end # module SimpleCov


