# frozen_string_literal: true

# Bundler puts the project's lib/ on the load path for both `rake man`
# and the spec suite, the only two callers.
require "simplecov/cli"
require "simplecov/version"

# Builds man/simplecov.1 from the usage document, the same single
# source the help text and the generated shell completions come from,
# so the page cannot drift from what the commands accept. `rake man`
# writes the artifact and spec/man_page_spec.rb fails when the
# committed copy is stale.
module ManPage
  extend self

  # Usage.text interpolates the process's resolved default paths; the
  # man page wants the plain defaults a fresh project sees, whatever
  # directory the generator runs from.
  module Defaults
    extend self

    def coverage_dir = "coverage"
    def default_input = "coverage/coverage.json"
    def default_report = "coverage/index.html"
    def default_resultset = "coverage/.resultset.json"
  end

  def build
    [header, name_section, synopsis_section, description_section, commands_section,
     options_section, environment_section, files_section, see_also_section].join("\n") << "\n"
  end

  def sections
    SimpleCov::CLI::Usage.text(Defaults).split("\n\n")
  end

  # [invocation, description] pairs from the Commands table, e.g.
  # ["watch <command...>", "Re-run <command> on save..."]. Rows whose
  # description wrapped contribute only their first line, which stands
  # alone by design.
  def command_rows
    sections.fetch(1).lines.drop(1).filter_map do |row|
      match = row.strip.match(/\A(.*?)\s{2,}(\S.*)\z/)
      match&.captures
    end
  end

  def options_for(command)
    sections.select { |section| SimpleCov::CLI::Usage.section_for?(section, command) }
            .flat_map { |section| SimpleCov::CLI::Completions.section_options(section) }
  end

  def escape(text)
    text.gsub("\\") { "\\e" }.gsub("-") { "\\-" }
  end

  # Escaped body text wrapped for readable roff source. A wrapped line
  # must not begin with a control character (`.` or `'`), so those get
  # the `\&` zero-width guard.
  def paragraph(text)
    wrap(escape(text).split).map { |words| guard_control(words.join(" ")) }.join("\n")
  end

  def wrap(words)
    words.each_with_object([[]]) do |word, acc|
      acc << [] if acc.last.any? && (acc.last.sum(&:length) + acc.last.size + word.length) > 78
      acc.last << word
    end
  end

  def guard_control(line)
    line.start_with?(".", "'") ? "\\&#{line}" : line
  end

  # A literal date keeps the artifact deterministic (Date.today would
  # fail the freshness spec every day); bump it when it matters.
  DATE = "2026-08-24"

  def header
    %(.TH SIMPLECOV 1 "#{DATE}" "simplecov #{SimpleCov::VERSION}" "User Commands")
  end

  def name_section
    ".SH NAME\n#{escape('simplecov - coverage reports and questions from the terminal')}"
  end

  def synopsis_section
    ".SH SYNOPSIS\n.B simplecov\n.I command\n.RI [ options ]"
  end

  def description_section
    <<~ROFF.chomp
      .SH DESCRIPTION
      #{paragraph('The simplecov command reads the JSON report a SimpleCov run writes next to its HTML report ' \
                  '(coverage/coverage.json by default) and answers coverage questions from the terminal. ' \
                  "Default paths follow SimpleCov.coverage_dir from a project's .simplecov when one is present. " \
                  'Every command answers --help with its own usage.')}
    ROFF
  end

  def commands_section
    entries = command_rows.map { |invocation, desc| ".TP\n.B #{escape(invocation)}\n#{paragraph(desc)}" }
    [".SH COMMANDS", *entries].join("\n")
  end

  def options_section
    blocks = command_rows.filter_map do |invocation, _desc|
      options = options_for(invocation.split.fetch(0))
      next if options.empty?

      [".SS #{invocation.split.fetch(0)}", *options.map { |option| option_entry(option) }].join("\n")
    end
    [".SH OPTIONS", *blocks].join("\n")
  end

  def option_entry(option)
    flags = [option[:short], option[:long]].compact.join(", ")
    flags += " #{option[:arg]}" if option[:arg]
    ".TP\n.B #{escape(flags)}\n#{paragraph(option[:desc])}"
  end

  def environment_section
    entries = {
      "NO_COLOR" => "Disable colorized output. FORCE_COLOR forces it on, and --no-color beats both.",
      "SIMPLECOV_MERGE_TIMEOUT" => "Override merge_timeout in seconds. The watch command sets it for child runs " \
                                   "so subset re-runs keep merging into a whole report."
    }.map { |variable, desc| ".TP\n.B #{escape(variable)}\n#{paragraph(desc)}" }
    [".SH ENVIRONMENT", *entries].join("\n")
  end

  def files_section
    entries = {
      "coverage/coverage.json" => "The JSON report the read-only commands consume. The bundled HTML formatter " \
                                  "writes it alongside index.html.",
      "coverage/.resultset.json" => "The merged raw resultset the merge command reads and writes.",
      ".simplecov" => "Project configuration. Its SimpleCov.coverage_dir setting moves every default path above."
    }.map { |path, desc| ".TP\n.B #{escape(path)}\n#{paragraph(desc)}" }
    [".SH FILES", *entries].join("\n")
  end

  def see_also_section
    ".SH SEE ALSO\n#{paragraph('Full documentation with examples for every command lives in docs/CLI.md ' \
                               'in the source tree and at https://github.com/simplecov-ruby/simplecov')}"
  end
end
