#
# A ridiculously simple formatter for SimpleCov results.
#
class SimpleCov::Formatter::SimpleFormatter
  # Takes a SimpleCov::Result and generates a string out of it
  def format(result)
    output = ""

    result.groups.each do |name, files|
      output << "Group: #{name}\n"
      output << "="*40
      output << "\n"
      files.each do |file|
        output << "#{file.filename} (coverage: #{file.covered_percent.round(2)}%)\n"
      end
      output << "\n"
    end

    if result.reports.count > 0
      output << "Reports:\n\n"
    end
    result.reports.each do |report|
      output << "Report: " + report[:type].to_s + "\n"
      output << report.to_s + "\n"
      output << "\n"
    end
    output
  end
end
