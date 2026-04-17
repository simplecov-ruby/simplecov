# frozen_string_literal: true

module SimpleCov
  module Formatter
    class HTMLFormatter
      # Helpers for rendering coverage bars, cells, and summaries in ERB templates.
      module CoverageHelpers
        def coverage_bar(pct)
          css = coverage_css_class(pct)
          width = Kernel.format("%.1f", pct.floor(1))
          fill = %(<div class="coverage-bar__fill coverage-bar__fill--#{css}" style="width: #{width}%"></div>)
          %(<div class="bar-sizer"><div class="coverage-bar">#{fill}</div></div>)
        end

        def coverage_cells(pct, covered, total, type:, totals: false)
          cov_cls, num_cls, den_cls, order = coverage_cell_attrs(pct, type, totals)
          pct_str = Kernel.format("%.2f", pct.floor(2))
          bar_and_pct = %(<div class="coverage-cell">#{coverage_bar(pct)}<span class="coverage-pct">#{pct_str}%</span></div>)
          %(<td class="#{cov_cls}"#{order}>#{bar_and_pct}</td>) +
            %(<td class="#{num_cls}">#{fmt(covered)}/</td>) +
            %(<td class="#{den_cls}">#{fmt(total)}</td>)
        end

        def coverage_header_cells(label, type, covered_label, total_label)
          <<~HTML
            <th class="cell--coverage">
              <div class="th-with-filter">
                <span class="th-label">#{label}</span>
                <div class="col-filter__coverage">
                  <select class="col-filter__op" data-type="#{type}"><option value="lt">&lt;</option><option value="lte" selected>&le;</option><option value="eq">=</option><option value="gte">&ge;</option><option value="gt">&gt;</option></select>
                  <span class="col-filter__pct-wrap"><input type="number" class="col-filter__value" min="0" max="100" data-type="#{type}" value="100" step="any"></span>
                </div>
              </div>
            </th>
            <th class="cell--numerator">#{covered_label}</th>
            <th class="cell--denominator">#{total_label}</th>
          HTML
        end

        def file_data_attrs(source_file)
          build_data_attr_pairs(source_file).map { |k, v| %(data-#{k}="#{v}") }.join(" ")
        end

        def coverage_type_summary(type, label, summary, enabled:, **opts)
          return disabled_summary(type, label) unless enabled

          enabled_type_summary(type, label, summary.fetch(type.to_sym), opts)
        end

        def coverage_summary(source_file, show_method_toggle: false)
          stats = source_file.coverage_statistics
          _summary = {
            line: stats[:line],
            branch: stats[:branch],
            method: stats[:method],
            show_method_toggle: show_method_toggle
          }
          template("coverage_summary").result(binding)
        end

      private

        def totals_cell_attrs(type, css)
          ["cell--coverage strong t-totals__#{type}-pct #{css}",
           "cell--numerator strong t-totals__#{type}-num",
           "cell--denominator strong t-totals__#{type}-den", ""]
        end

        def regular_cell_attrs(pct, type, css)
          ["cell--coverage cell--#{type}-pct #{css}",
           "cell--numerator", "cell--denominator",
           %( data-order="#{Kernel.format('%.2f', pct)}")]
        end

        def coverage_cell_attrs(pct, type, totals)
          css = coverage_css_class(pct)
          totals ? totals_cell_attrs(type, css) : regular_cell_attrs(pct, type, css)
        end

        def build_data_attr_pairs(source_file)
          covered = source_file.covered_lines.count
          pairs = {"covered-lines" => covered, "relevant-lines" => covered + source_file.missed_lines.count}
          append_branch_attrs(pairs, source_file)
          append_method_attrs(pairs, source_file)
          pairs
        end

        def append_branch_attrs(pairs, source_file)
          return unless branch_coverage?

          pairs["covered-branches"] = source_file.covered_branches.count
          pairs["total-branches"] = source_file.total_branches.count
        end

        def append_method_attrs(pairs, source_file)
          return unless method_coverage?

          pairs["covered-methods"] = source_file.covered_methods.count
          pairs["total-methods"] = source_file.methods.count
        end

        def enabled_type_summary(type, label, stats, opts)
          css = coverage_css_class(stats.percent)
          missed = stats.missed
          parts = [
            %(<div class="t-#{type}-summary">\n    #{label}: ),
            %(<span class="#{css}"><b>#{Kernel.format('%.2f', stats.percent.floor(2))}%</b></span>),
            %(<span class="coverage-cell__fraction"> #{stats.covered}/#{stats.total} #{opts.fetch(:suffix, 'covered')}</span>)
          ]
          parts << missed_summary_html(missed, opts.fetch(:missed_class, "red"), opts.fetch(:toggle, false)) if missed.positive?
          parts << "\n  </div>"
          parts.join
        end

        def disabled_summary(type, label)
          %(<div class="t-#{type}-summary">\n    #{label}: <span class="coverage-disabled">disabled</span>\n  </div>)
        end

        def missed_summary_html(count, missed_class, toggle)
          missed = if toggle
                     %(<a href="#" class="t-missed-method-toggle"><b>#{count}</b> missed</a>)
                   else
                     %(<span class="#{missed_class}"><b>#{count}</b> missed</span>)
                   end
          %(<span class="coverage-cell__fraction">,</span>\n    #{missed})
        end
      end
    end
  end
end
