class SimpleCov::Formatter::SimpleFormatter
  def format(result)
    result.groups.each do |name, files|
      puts "Group: #{name}"
      puts "="*40
      files.each do |file|
        puts "#{file.filename} (coverage: #{file.covered_percent.round(2)}%)"
      end
    end
  end
end