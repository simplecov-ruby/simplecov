# frozen_string_literal: true

require "erb"
require "fileutils"
require "time"
require_relative "html_formatter/view_helpers"

module SimpleCov
  module Formatter
    # Generates an HTML coverage report from SimpleCov results.
    class HTMLFormatter
      VERSION = "0.13.2"

      # Only have a few content types, just hardcode them
      CONTENT_TYPES = {
        ".js" => "text/javascript",
        ".png" => "image/png",
        ".gif" => "image/gif",
        ".css" => "text/css"
      }.freeze

      include ViewHelpers

      def initialize(silent: false, inline_assets: false)
        @branch_coverage = SimpleCov.branch_coverage?
        @method_coverage = SimpleCov.method_coverage?
        @templates = {}
        @inline_assets = inline_assets || ENV.key?("SIMPLECOV_INLINE_ASSETS")
        @public_assets_dir = File.join(__dir__, "html_formatter/public/")
        @silent = silent
      end

      def format(result)
        unless @inline_assets
          Dir[File.join(@public_assets_dir, "*")].each do |path|
            FileUtils.cp_r(path, asset_output_path, remove_destination: true)
          end
        end

        File.write(File.join(output_path, "index.html"), template("layout").result(binding), mode: "wb")
        puts output_message(result) unless @silent
      end

    private

      def branch_coverage?
        @branch_coverage
      end

      def method_coverage?
        @method_coverage
      end

      def output_message(result)
        lines = ["Coverage report generated for #{result.command_name} to #{output_path}"]
        lines << "Line coverage: #{render_stats(result, :line)}"
        lines << "Branch coverage: #{render_stats(result, :branch)}" if branch_coverage?
        lines << "Method coverage: #{render_stats(result, :method)}" if method_coverage?
        lines.join("\n")
      end

      def template(name)
        @templates[name] ||= ERB.new(File.read(File.join(__dir__, "html_formatter/views/", "#{name}.erb")), trim_mode: "-")
      end

      def output_path
        SimpleCov.coverage_path
      end

      def asset_output_path
        @asset_output_path ||= File.join(output_path, "assets", VERSION).tap do |path|
          FileUtils.mkdir_p(path)
        end
      end

      def assets_path(name)
        return asset_inline(name) if @inline_assets

        File.join("./assets", VERSION, name)
      end

      def asset_inline(name)
        path = File.join(@public_assets_dir, name)
        base64_content = [File.read(path)].pack("m0")
        "data:#{CONTENT_TYPES.fetch(File.extname(name))};base64,#{base64_content}"
      end

      def formatted_source_file(source_file)
        template("source_file").result(binding)
      rescue Encoding::CompatibilityError => e
        puts "Encoding problems with file #{source_file.filename}. Simplecov/ERB can't handle non ASCII characters in filenames. Error: #{e.message}."
        %(<div class="source_table" id="#{id(source_file)}"><div class="header"><h2>Encoding Error</h2><p>#{ERB::Util.html_escape(e.message)}</p></div></div>)
      end

      def formatted_file_list(title, source_files)
        template("file_list").result(binding)
      end

      def render_stats(result, criterion)
        stats = result.coverage_statistics.fetch(criterion)
        Kernel.format("%<covered>d / %<total>d (%<percent>.2f%%)", covered: stats.covered, total: stats.total, percent: stats.percent)
      end
    end
  end
end
