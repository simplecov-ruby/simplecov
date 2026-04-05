# frozen_string_literal: true

Then /^I should see the groups:$/ do |table|
  expected_groups = table.hashes
  expect(page).to have_css("#content .file_list_container", count: expected_groups.count)

  expected_groups.each do |group|
    with_scope "#content ##{group['name'].gsub(/[^a-z]/i, '')}.file_list_container" do
      file_count_in_group = page.all("a.src_link").count
      expect(file_count_in_group).to eq(group["files"].to_i)

      # New simplecov-html: group name/coverage in hidden spans; old: in h2
      if page.has_css?(".group_name", visible: false, wait: 0)
        expect(find(".group_name", visible: :all).text).to include(group["name"])
        expect(find(".covered_percent", visible: :all).text).to include(group["coverage"])
      else
        with_scope "h2" do
          expect(page).to have_content(group["name"])
          expect(page).to have_content(group["coverage"])
        end
      end
    end
  end
end

Then /^I should see the source files:$/ do |table|
  expected_files = table.hashes
  available_source_files = all(".t-file", visible: true, count: expected_files.count)

  include_branch_coverage = table.column_names.include?("branch coverage")

  files = available_source_files.map do |file_row|
    # Try selectors in order: newest → older → oldest simplecov-html
    coverage_text =
      if file_row.has_css?(".cell--line-pct", wait: 0)
        file_row.find(".cell--line-pct").text
      elsif file_row.has_css?(".t-file__coverage .coverage-cell__pct", wait: 0)
        file_row.find(".t-file__coverage .coverage-cell__pct").text
      else
        file_row.find(".t-file__coverage").text
      end

    coverage_data = {"name" => file_row.find(".t-file__name").text, "coverage" => coverage_text}

    if include_branch_coverage
      coverage_data["branch coverage"] =
        if file_row.has_css?(".cell--branch-pct", wait: 0)
          file_row.find(".cell--branch-pct").text
        elsif file_row.has_css?(".t-file__branch-coverage .coverage-cell__pct", wait: 0)
          file_row.find(".t-file__branch-coverage .coverage-cell__pct").text
        else
          file_row.find(".t-file__branch-coverage").text
        end
    end

    coverage_data
  end

  expect(files.sort_by { |coverage_data| coverage_data["name"] }).to eq(expected_files.sort_by { |coverage_data| coverage_data["name"] })
end

Then /^there should be (\d+) skipped lines in the source files$/ do |expected_count|
  # Materialize all source files (renders them from coverage data), then count skipped lines
  count = page.evaluate_script(<<~JS)
    (function() {
      // Check for pre-rendered templates (old simplecov-html)
      var templates = document.querySelectorAll('.source_files template');
      if (templates.length > 0) {
        return Array.from(templates).reduce(function(sum, t) {
          return sum + t.content.querySelectorAll('ol li.skipped').length;
        }, 0);
      }
      // New architecture: count skipped lines directly from coverage data
      if (window.SIMPLECOV_DATA) {
        var count = 0;
        var coverage = window.SIMPLECOV_DATA.coverage;
        Object.keys(coverage).forEach(function(fn) {
          var lines = coverage[fn].lines;
          lines.forEach(function(l) { if (l === 'ignored') count++; });
        });
        return count;
      }
      return document.querySelectorAll('.source_table ol li.skipped').length;
    })()
  JS
  expect(count).to eq(expected_count.to_i)
end

Then /^I should see a (.+) coverage summary of (\d+)\/(\d+)( for the file)?$/ do |coverage_type, hit, total, for_file|
  missed = total - hit

  if for_file
    # File detail view: check the summary in the dialog (new) or source_table (old)
    selector = page.has_css?("#source-dialog[open]", wait: 0) ? "#source-dialog .t-#{coverage_type}-summary" : ".source_table .t-#{coverage_type}-summary"
    summary_text = find(selector, visible: false).text
  else
    # Try new format: sum data attributes from file rows
    attr_map = {"line" => %w[covered-lines relevant-lines], "branch" => %w[covered-branches total-branches]}
    covered_attr, total_attr = attr_map.fetch(coverage_type)
    actual_covered, actual_total = page.evaluate_script(<<~JS)
      (function() {
        var rows = document.querySelectorAll('.file_list_container .t-file[data-#{covered_attr}]');
        if (rows.length === 0) return null;
        var covered = 0, total = 0;
        rows.forEach(function(r) { covered += parseInt(r.getAttribute('data-#{covered_attr}') || '0'); total += parseInt(r.getAttribute('data-#{total_attr}') || '0'); });
        return [covered, total];
      })()
    JS

    if actual_covered
      actual_missed = actual_total - actual_covered
      summary_text = "#{actual_covered}/#{actual_total} #{actual_missed} missed"
    else
      # Old simplecov-html: find the summary text directly
      summary_text = first(".t-#{coverage_type}-summary", visible: false).text
    end
  end

  expect(summary_text).to match(/#{hit}\/#{total}.*#{missed}|#{total} .+ #{hit} .+ #{missed}/)
end

When /^I open the detailed view for "(.+)"$/ do |file_path|
  click_link(file_path, class: "src_link", title: file_path)

  expect(page).to have_css("#source-dialog[open]", visible: true)
  expect(page).to have_css("#source-dialog-title", visible: true, text: file_path)
end

When "I close the detailed view" do
  find(".source-dialog__close").click
end

Then /^I should see coverage branch data like "(.+)"$/ do |text|
  hits_found = page.evaluate_script("document.querySelector('#source-dialog-body').innerHTML.includes('#{text}')")
  expect(hits_found).to be true
end
