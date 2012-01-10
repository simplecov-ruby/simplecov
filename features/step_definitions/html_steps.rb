module GroupHelpers
  def available_groups
    all('#content .file_list_container')
  end

  def available_source_files
    all('.source_files .source_table')
  end
end
World(GroupHelpers)


Then /^I should see the groups:$/ do |table|
  expected_groups = table.hashes
  # Given group names should be the same number than those rendered in report
  expected_groups.count.should == available_groups.count

  # Verify each of the expected groups has a file list container and corresponding title and coverage number
  # as well as the correct number of links to files.
  expected_groups.each do |group|
    with_scope "#content ##{group["name"].gsub(/[^a-z]/i, '')}.file_list_container" do
      file_count_in_group = page.all('a.src_link').count
      file_count_in_group.should == group["files"].to_i

      with_scope "h2" do
        page.should have_content(group["name"])
        page.should have_content(group["coverage"])
      end
    end
  end
end

Then /^I should see the source files:$/ do |table|
  expected_files = table.hashes
  expected_files.length.should == available_source_files.count

  # Find all filenames and their coverage present in coverage report
  files = available_source_files.map {|f| {"name" => f.find('h3').text, "coverage" => f.find('.header span').text} }

  files.sort_by {|hsh| hsh["name"] }.should == expected_files.sort_by {|hsh| hsh["name"] }
end

Then /^there should be (\d+) skipped lines in the source files$/ do |expected_count|
  all(".source_table ol li.skipped").count.should == expected_count.to_i
end
