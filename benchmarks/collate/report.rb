# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "breakdown"
require_relative "format"
require_relative "fixture"

module CollateBenchmark
  class Report
    PHASE_ROW = "%-16<phase>s %12<seconds>s %12<delta>s"
    BREAKDOWN_ROW = "%-38<label>s %9<seconds>s %10<calls>s %6.1<share>f%%"

    def initialize(run:, timings:, baseline_label:)
      @run = run
      @timings = timings
      @baseline_label = baseline_label
    end

    def header(fixture)
      puts
      puts "SimpleCov collate benchmark — #{@run.label}"
      print_summary(fixture)
      puts
    end

    def print_summary(fixture)
      merge = (@run.processes > 1) ? "across #{@run.processes} forked workers" : "serial, in this process"
      puts "  resultsets:   #{fixture.resultset_paths.size}"
      puts "  merge:        #{merge}"
      puts "  fixture:      #{fixture_summary(fixture)}"
      puts "  skipping:     #{@run.skip.to_a.join(", ")}" if @run.skip.any?
    end

    def fixture_summary(fixture)
      "#{fixture.file_count} files, #{fixture.line_count} lines, " \
        "#{fixture.condition_count} branch conditions (1/#{@run.scale} scale)"
    end

    def call(peak_rss:, files_reported:)
      baseline = load_baseline
      phase_table(baseline)
      breakdown_table if @run.breakdown
      footer(peak_rss, files_reported)
      write(peak_rss, files_reported)
    end

    private

    def phase_table(baseline)
      puts
      puts format(PHASE_ROW, phase: "phase", seconds: "seconds", delta: "vs baseline")
      puts "-" * 41
      Runner::PHASES.each { |name| phase_row(name, @timings[name], baseline&.dig("phases", name)) }
      puts "-" * 41
      phase_row("total", total, baseline&.fetch("total", nil))
    end

    def phase_row(name, seconds, was)
      return unless seconds

      puts format(PHASE_ROW, phase: name, seconds: Format.duration(seconds),
        delta: was ? Format.delta(seconds, was) : "-")
    end

    def breakdown_table
      merge = @timings["merge"]
      rows = Breakdown.rows(merge)

      puts
      puts "inside merge (#{Format.duration(merge)})"
      puts "-" * 66
      rows.each { |row| puts breakdown_row(row) }
      puts breakdown_row(unattributed_row(rows, merge))
    end

    def unattributed_row(rows, merge)
      seconds = merge - rows.sum(&:seconds)
      Breakdown::Row.new(label: "unattributed", seconds: seconds, calls: "", share: seconds / merge * 100)
    end

    def breakdown_row(row)
      format(BREAKDOWN_ROW, label: row.label, seconds: Format.duration(row.seconds),
        calls: row.calls, share: row.share)
    end

    def footer(peak_rss, files_reported)
      puts
      puts "  peak RSS:        #{Format.bytes(peak_rss)}"
      puts "  files reported:  #{files_reported}" if files_reported
      puts "  fixture dir:     #{Fixture.dir}"
      puts "  timings:         #{path_for(@run.label)}"
    end

    def load_baseline
      return nil unless @baseline_label

      path = path_for(@baseline_label)
      unless File.exist?(path)
        warn "[collate] no baseline timings at #{path}"
        return nil
      end

      JSON.parse(File.read(path)).tap { |baseline| warn_if_incomparable(baseline) }
    end

    def warn_if_incomparable(baseline)
      return if baseline["resultsets"] == @run.resultsets_used && baseline["scale"] == @run.scale

      warn "[collate] baseline '#{@baseline_label}' merged #{baseline["resultsets"]} resultsets at " \
           "1/#{baseline["scale"]} scale, this run merged #{@run.resultsets_used} at 1/#{@run.scale} — " \
           "the deltas below are not comparable"
    end

    def write(peak_rss, files_reported)
      FileUtils.mkdir_p(Fixture::TIMINGS_DIR)
      timings = {
        "label" => @run.label, "scale" => @run.scale, "resultsets" => @run.resultsets_used,
        "processes" => @run.processes, "phases" => @timings, "total" => total, "peak_rss" => peak_rss,
        "files_reported" => files_reported, "ruby" => RUBY_DESCRIPTION,
        "instrumented" => @run.breakdown
      }
      File.write(path_for(@run.label), JSON.pretty_generate(timings))
    end

    def path_for(label)
      File.join(Fixture::TIMINGS_DIR, "#{label}.json")
    end

    def total
      @timings.values.sum
    end
  end
end
