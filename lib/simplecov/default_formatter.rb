# frozen_string_literal: true

DEFAULT_FORMATTER = "HTML"

def constantize_formatter(formatter)
  SimpleCov::Formatter.const_get("#{formatter}Formatter")
rescue StandardError
  warn "SimpleCov #{f} format unrecognized"
  nil
end

def validate_formatters(formatters)
  raise "None valid formatter was given. Valid default values are 'HTML' and 'JSON'" unless formatters.any?

  formatters
end

def fetch_env_formatters
  formatters = ENV.fetch("SIMPLECOV_FORMATTERS") { DEFAULT_FORMATTER }
  formatters.split(",")
end

def json_formatter_for_codeclimate(formatters)
  formatters.push("JSON") if ENV.fetch("CC_TEST_REPORTER_ID") { nil }
  formatters
end

def formatters
  formatters = fetch_env_formatters
  formatters = json_formatter_for_codeclimate(formatters)
  formatters.map! do |f|
    constantize_formatter(f)
  end
  formatters.compact!
  formatters.uniq!

  validate_formatters(formatters)
end

def configure_formatters(formatters)
  if formatters.count > 1
    SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(formatters)
  else
    SimpleCov.formatter = formatters.first
  end
end

configure_formatters(formatters)
