v0.5.4 (2011-10-12)
===================

  * Do not give exit code 0 when there are exceptions prior to tests 
    (see https://github.com/colszowka/simplecov/issues/41, thanks @nbogie)
  * The API for building custom filter classes is now more obvious, using #matches? instead of #passes? too. 
    (see https://github.com/colszowka/simplecov/issues/85, thanks @robinroestenburg)
  * Mailers are now part of the Rails adapter as their own group (see 
    https://github.com/colszowka/simplecov/issues/79, thanks @geetarista)
  * Removed fix for JRuby 1.6 RC1 float bug because it's been fixed 
    (see https://github.com/colszowka/simplecov/issues/86)
  * Readme formatted in Markdown :)

v0.5.3 (2011-09-13)
===================

  * Fix for encoding issues that came from the nocov processing mechanism
    (see https://github.com/colszowka/simplecov/issues/71)
  * :nocov: lines are now actually being reflected in the HTML report and are marked in yellow.
  
  * The Favicon in the HTML report is now determined by the overall coverage and will have the color
    that the coverage percentage gets as a css class to immediately indicate coverage status on first sight.
    
  * Introduced SimpleCov::SourceFile::Line#status method that returns the coverage status
    as a string for this line - made SimpleCov::HTML use that.
  * Refactored nocov processing and made it configurable using SimpleCov.ncov_token (or it's
    alias SimpleCov.skip_token)

v0.5.2 (2011-09-12)
===================

  * Another fix for a bug in JSON processing introduced with MultiJSON in 0.5.1
    (see https://github.com/colszowka/simplecov/pull/75, thanks @sferik)

v0.5.1 (2011-09-12)
===================
**Note: Yanked 2011-09-12 because the MultiJSON-patch had a crucial bug**

  * Fix for invalid gemspec dependency string (see https://github.com/colszowka/simplecov/pull/70,
    http://blog.rubygems.org/2011/08/31/shaving-the-yaml-yacc.html, thanks @jspradlin)
    
  * Added JSON in the form of the multi_json gem as dependency for those cases when built-in JSON
    is unavailable (see https://github.com/colszowka/simplecov/issues/72 
    and https://github.com/colszowka/simplecov/pull/74, thanks @sferik)

v0.5.0 (2011-09-09)
===================
**Note: Yanked 2011-09-09 because of trouble with the gemspec.**

  * JSON is now used instead of YAML for resultset caching (used for merging). Should resolve
    a lot of problems people used to have because of YAML parser errors.

  * There's a new adapter 'test_frameworks'. Use it outside of Rails to remove `test/`,
    `spec/`, `features/` and `autotest/` dirs from your coverage reports, either directly
    with `SimpleCov.start 'test_frameworks'` or with `SimpleCov.load_adapter 'test_frameworks'`

  * SimpleCov configuration can now be placed centrally in a text file `.simplecov`, which will
    be automatically read on `require 'simplecov'`. This makes using custom configuration like
    groups and filters across your test suites much easier as you only have to specify your config
    once. Just put the whole `SimpleCov.start (...)` code into `APP_ROOT/.simplecov`

  * Lines can now be skipped by using the :nocov: flag in comments that wrap the code that should be
    skipped, like in this example (thanks @phillipkoebbe)

    <pre>
      #:nocov:
      def skipped
    	  @foo * 2
      end
      #:nocov:
    </pre>

  * Moved file set coverage analytics from simplecov-html to SimpleCov::FileList, a new subclass
    of Array that is always returned for SourceFile lists (i.e. in groups) and can now be used
    in all formatters without the need to roll your own.

  * The exceptions you used to get after removing some code and re-running your tests because SimpleCov
    couldn't find the cached source lines should be resolved (thanks @goneflyin)

  * Coverage strength metric: Average hits/line per source file and result group (thanks @trans)

  * Finally, SimpleCov has an extensive Cucumber test suite

  * Full compatibility with Ruby 1.9.3.preview1

HTML Formatter:
---------------

  * The display of source files has been improved a lot. Weird scrolling trouble, out-of-scope line hit counts
    and such should be a thing of the past. Also, it is prettier now.
  * Source files are now syntax highlighted
  * File paths no longer have that annoying './' in front of them
