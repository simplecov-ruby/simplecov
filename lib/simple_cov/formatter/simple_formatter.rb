class SimpleCov::Formatter::SimpleFormatter
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
    output
  end
end