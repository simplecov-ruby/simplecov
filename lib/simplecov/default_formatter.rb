DEFAULT_FORMATTER = "HTML"

configured_formatters = ENV.fetch("SIMPLECOV_FORMATTERS") { DEFAULT_FORMATTER }
configured_formatters = configured_formatters.split(",")
configured_formatters.map! do |f|
  SimpleCov::Formatter.const_get("#{f}Formatter") rescue nil
end
configured_formatters.compact

if configured_formatters.count > 1
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(configured_formatters)
else
  SimpleCov.formatter = configured_formatters.first
end
