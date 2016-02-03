require "simplecov"
require "rspec"

SimpleCov.coverage_dir("tmp/coverage")

def source_fixture(filename)
  File.expand_path(File.join(File.dirname(__FILE__), "fixtures", filename))
end

# Taken from http://stackoverflow.com/questions/4459330/how-do-i-temporarily-redirect-stderr-in-ruby
require "stringio"

def capture_stderr
  # The output stream must be an IO-like object. In this case we capture it in
  # an in-memory IO object so we can return the string value. You can assign any
  # IO object here.
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
  $stderr.string
ensure
  # Restore the previous value of stderr (typically equal to STDERR).
  $stderr = previous_stderr
end

RSpec.configure do |config|
  project_path_regexp = Regexp.escape(Dir.pwd)
  # Fail tests if Kernel#warn is executed
  config.around(:example) do |example|
    original_warn = Kernel.method(:warn)
    begin
      kernel_warn_callers = []
      Kernel.class_exec do
        remove_method(:warn)
        define_method(:warn) do |*args, &block|
          kernel_warn_callers << caller.first
          original_warn.call(*args, &block)
        end
      end
      example.call
      kernel_warn_callers.keep_if { |c| c =~ /^#{project_path_regexp}/ }
      expect(kernel_warn_callers).to be_empty, "Kernel\#warn called from: #{kernel_warn_callers.join(', ')}."
    ensure
      Kernel.class_exec do
        remove_method(:warn)
        define_method(:warn, original_warn.to_proc)
      end
    end
  end
  # Fail tests if code generates runtime warnings
  config.around(:example) do |example|
    expect { example.call }
      .not_to output(/^#{project_path_regexp}\/.+:\d+: warning: /)
      .to_stderr
  end
end
