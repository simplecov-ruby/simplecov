# frozen_string_literal: true

require_relative "../formatter/multi_formatter"

module SimpleCov
  module Configuration
    attr_writer :formatter, :print_error_status

    BUILT_IN_FORMATS = {
      html: :HTMLFormatter, json: :JSONFormatter, simple: :SimpleFormatter, baseline: :BaselineFormatter
    }.freeze
    private_constant :BUILT_IN_FORMATS

    LAZY_FORMAT_REQUIRES = {html: "../../simplecov-html"}.freeze
    private_constant :LAZY_FORMAT_REQUIRES

    def formats(*names)
      return formatters if names.empty?

      self.formatters = names.map { |name| resolve_format(name) }
      formatters
    end

    def formatter(formatter = :__no_arg__)
      case formatter
      when :__no_arg__
        @formatter
      else
        @formatter = formatter || nil
      end
    end

    def formatters(formatters = :__no_arg__)
      case formatters
      when :__no_arg__
        configured = formatter
        configured ? [configured] : []
      else
        self.formatters = formatters
      end
    end

    # `nil`, `false`, and `[]` all opt out of formatting entirely. `false` is
    # normalized first, since `Array(false)` would otherwise smuggle it in as a
    # "formatter" that can only fail.
    def formatters=(formatters)
      @formatter = combined_formatter(Array(formatters || nil))
    end

    def color(value = :__no_arg__)
      return instance_variable_defined?(:@color) ? @color : :auto if value.eql?(:__no_arg__)

      self.color = _ = value
    end

    def color=(value)
      @color = value
    end

    def print_errors(value = :__no_arg__)
      return instance_variable_defined?(:@print_error_status) ? @print_error_status : true if value.eql?(:__no_arg__)

      self.print_errors = _ = value
    end

    def print_errors=(value)
      @print_error_status = value
    end

    def source_in_json(value = :__no_arg__)
      return instance_variable_defined?(:@source_in_json) ? @source_in_json : true if value.eql?(:__no_arg__)

      self.source_in_json = _ = value
    end

    def source_in_json=(value)
      @source_in_json = value
    end

    def print_error_status
      Deprecation.warn("`SimpleCov.print_error_status` is deprecated. " \
                       "Replace with `SimpleCov.print_errors` (same value).")
      instance_variable_defined?(:@print_error_status) ? @print_error_status : true
    end

    def nocov_token(nocov_token = nil)
      Deprecation.warn("`SimpleCov.nocov_token` and `SimpleCov.skip_token` are deprecated. " \
                       "Replace with `# simplecov:disable` / `# simplecov:enable` block comments.")
      current_nocov_token(nocov_token)
    end
    alias_method :skip_token, :nocov_token

    def current_nocov_token(value = nil)
      return @nocov_token if instance_variable_defined?(:@nocov_token) && value.nil?

      @nocov_token = value || "nocov"
    end

    private

    # An empty list is how a project opts out of formatting.
    def combined_formatter(formatters)
      return if formatters.empty?

      Formatter::MultiFormatter.new(formatters)
    end

    def resolve_format(name)
      return name unless name.instance_of?(Symbol)

      constant = BUILT_IN_FORMATS[name]
      unless constant
        raise ConfigurationError,
          "Unknown format #{name.inspect}. Built-in formats are :html, :json, :simple, and :baseline; " \
          "pass a formatter class or instance for anything else."
      end

      require_html_formatter(name)
      Formatter.const_get(constant)
    end

    # `formats :html` has to work in a process that never required the HTML
    # formatter, which under SIMPLECOV_NO_DEFAULTS nothing else has.
    def require_html_formatter(name)
      path = LAZY_FORMAT_REQUIRES[name]
      require_relative(path) if path
    end
  end
end
