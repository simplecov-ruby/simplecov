# Freedom patch because of not working absolute directories, see: https://github.com/cucumber/aruba/issues/478
# code taken directly from aruba 0.14.2 - roughly here: https://github.com/cucumber/aruba/blob/master/lib/aruba/api/core.rb#L122-L159
# rubocop:disable all
module Aruba
  module Api
    module Core
      def expand_path(file_name, dir_string = nil)
        # only line added, don't ask why but I couldn't get alias_method to work...
        return file_name if absolute?(file_name)
        check_for_deprecated_variables if Aruba::VERSION < '1'

        message = %(Filename "#{file_name}" needs to be a string. It cannot be nil or empty either.  Please use `expand_path('.')` if you want the current directory to be expanded.)

        fail ArgumentError, message unless file_name.is_a?(String) && !file_name.empty?

        aruba.logger.warn %(`aruba`'s working directory does not exist. Maybe you forgot to run `setup_aruba` before using it's API. This warning will be an error from 1.0.0) unless Aruba.platform.directory? File.join(aruba.config.root_directory, aruba.config.working_directory)

        if RUBY_VERSION < '1.9'
          prefix = file_name.chars.to_a[0].to_s
          rest = if file_name.chars.to_a[2..-1].nil?
                   nil
                 else
                   file_name.chars.to_a[2..-1].join
                 end
        else
          prefix = file_name[0]
          rest = file_name[2..-1]
        end

        if aruba.config.fixtures_path_prefix == prefix
          path = File.join(*[aruba.fixtures_directory, rest].compact)

          fail ArgumentError, %(Fixture "#{rest}" does not exist in fixtures directory "#{aruba.fixtures_directory}". This was the one we found first on your system from all possible candidates: #{aruba.config.fixtures_directories.map { |p| format('"%s"', p) }.join(', ')}.) unless Aruba.platform.exist? path

          path
        elsif '~' == prefix
          path = with_environment do
            ArubaPath.new(File.expand_path(file_name))
          end

          fail ArgumentError, 'Expanding "~/" to "/" is not allowed' if path.to_s == '/'
          fail ArgumentError, %(Expanding "~/" to a relative path "#{path}" is not allowed) unless path.absolute?

          path.to_s
        else
          directory = File.join(aruba.root_directory, aruba.current_directory)
          ArubaPath.new(File.join(*[directory, dir_string, file_name].compact)).expand_path.to_s
        end
      end
    end
  end
end
# rubocop:enable all
