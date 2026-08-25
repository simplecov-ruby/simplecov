## Alternate coverage report formatters

The community around SimpleCov provides a whole bunch of alternate formatters beyond the bundled
HTML and JSON formatters.

If you have built or found one that is missing here, please send a Pull Request for this document!

### Terminal output

#### [simplecov-console](https://github.com/chetan/simplecov-console)
*by Chetan Sarva*

A simple console output formatter: a table of per-file coverage (branch coverage included) plus the missed lines, right in your terminal.

#### [simplecov-summary](https://github.com/inossidabile/simplecov-summary)
*by Boris Staal*

Prints a colored per-group coverage summary to the console at the end of a run.

#### [simplecov-stdout](https://github.com/cainlevy/simplecov-stdout)
*by Lance Ivy*

Prints actionable feedback straight to stdout: which of the files you touched are missing coverage, and where.

#### [simplecov-tdd](https://github.com/joshmfrankel/simplecov-tdd)
*by Josh Frankel*

Coverage feedback tuned for a test-driven workflow: reports on the file under test as you run its spec.

#### [simplecov-teamcity-summary](https://github.com/benc/simplecov-teamcity-summary)
*by Ben Cochez*

Reports the coverage summary through TeamCity service messages so it shows up on the build page.

#### [simplecov-t_wada](https://github.com/ysksn/simplecov-t_wada)
*by [Yosuke Kabuto](https://github.com/ysksn)*

t_wada AA formatter for SimpleCov

#### [simplecov-single_file_reporter](https://github.com/grosser/simplecov-single_file_reporter)
*by [Michael Grosser](http://grosser.it)*

A formatter that prints the coverage of the file under test when you run a single test file.

#### [simplecov-single_file](https://github.com/floor114/simplecov-single_file)
*by Taras Shpachenko*

Single file coverage reports for SimpleCov.

### HTML reports

#### [simplecov-tailwindcss](https://github.com/chiefpansancolt/simplecov-tailwindcss)
*by [Chiefpansancolt](https://github.com/chiefpansancolt)*

A TailwindCSS & TailwindUI Designed HTML formatter with clean and easy search of files with a tabular left Navigation.

#### [simplecov-material](https://github.com/chiefpansancolt/simplecov-material)
*by [Chiefpansancolt](https://github.com/chiefpansancolt)*

A Material Design HTML formatter that is clean and easy to read.

#### [simplecov-hypertext](https://github.com/first-try-software/simplecov-hypertext)
*by Christoph Olszowka, Alan Ridlehoover, and Fito von Zastrow*

An HTML formatter built to stay fast and navigable on large codebases.

#### [simplecov_html_inline](https://github.com/tobyhs/simplecov_html_inline)
*by Toby Hsieh*

A variant of simplecov-html that inlines its assets, producing a report that survives being passed around as a single CI artifact.

#### [simplecov-inline-html](https://github.com/JonRowe/simplecov-inline-html)
*by Jon Rowe*

Inline HTML formatter for SimpleCov.

#### [simplecov-phpunit](https://github.com/TheFox/simplecov-phpunit)
*by Christian Mayer*

A PHPUnit-style HTML report, for those who came to Ruby from PHP and miss it.

### Machine-readable formats for CI and tooling

#### [simplecov-cobertura](https://github.com/jessebs/simplecov-cobertura)
*by Jesse Bowes*

A formatter that generates Cobertura XML, consumed by many CI services (GitLab merge-request coverage among them).

#### [simplecov-lcov](https://github.com/fortissimo1997/simplecov-lcov)
*by fortissimo1997*

lcov formatter for SimpleCov

#### [simplecov_lcov_formatter](https://rubygems.org/gems/simplecov_lcov_formatter)
*by t-mario-y*

LCOV formatter positioned as a successor to simplecov-lcov.

#### [undercover](https://github.com/grodowski/undercover)
*by Jan Grodowski*

Warns about methods and blocks a git diff changed that lack test coverage. Its `SimpleCov::Formatter::Undercover`
writes the report data for the separate `undercover` CLI to read, by default to the same `coverage/coverage.json`
path the bundled formatters own, so whichever formatter runs last decides that file's shape. The bundled
[`simplecov patch`](CLI.md) command answers the related per-line question (is the code this change touched
covered?) without an extra gem.

#### [simplecov-json](https://github.com/vicentllongo/simplecov-json)
*by Vicent Llongo*

JSON formatter for SimpleCov

#### [simplecov_compact_json](https://rubygems.org/gems/simplecov_compact_json)
*by Coraline Ada Ehmke*

A lightweight, summary-level JSON formatter.

#### [simplecov-oj](https://github.com/mhenrixon/simplecov-oj)
*by Mikael Henriksson*

JSON formatter that serializes through Oj, for large projects where the standard JSON dump gets slow.

#### [simplecov-csv](https://github.com/fguillen/simplecov-csv)
*by Fernando Guillen*

CSV formatter for SimpleCov

#### [simplecov-rcov](https://github.com/fguillen/simplecov-rcov)
*by Fernando Guillen*

"The target of this formatter is to cheat on Hudson so I can use the Ruby metrics plugin with SimpleCov."

#### [simplecov-rcov-text](https://github.com/kina/simplecov-rcov-text)
*by William "Kina"*

Generates the `rcov.txt` file that metric_fu expects.

#### [simplecov-clover](https://github.com/mikian/simplecov-clover)
*by Mikko Kokkonen*

Generates Clover XML for Atlassian tooling such as Bamboo.

#### [simplecov-markdown](https://github.com/renuo/simplecov-markdown)
*by Alessandro Rodi*

A Markdown summary, handy for pasting into pull requests and chat.

#### [simplecov-review](https://github.com/kukicola/simplecov-review)
*by Karol Bąk*

Reports missed lines in a format for review tools like reviewdog, so coverage gaps surface as PR annotations.

#### [simplecov-ai](https://github.com/VitaliiLazebnyi/simplecov-ai)
*by Vitalii Lazebnyi*

Concise, deterministic Markdown coverage digests tailored for LLMs and autonomous agents.

### Coverage badges

#### [simplecov-badge](https://github.com/matthew342/simplecov-badge)
*by Matt Hale*

A formatter that generates a coverage badge for use in your project's readme using ImageMagick.

#### [simplecov-small-badge](https://github.com/marcgrimme/simplecov-small-badge)
*by Marc Grimme*

A formatter that generates a small coverage badge for use in your project's readme using the SVG.

#### [simplecov-formatter-badge](https://github.com/marocchino/simplecov-formatter-badge)
*by Shim Won*

Generates an SVG coverage badge locally, with no ImageMagick dependency.

#### [simplecov-shields-badge](https://github.com/niltonvasques/simplecov-shields-badge)
*by Nilton Vasques*

Generates a shields.io-style SVG coverage badge.

#### [simplecov_badger](https://github.com/traels-it/simplecov_badger)
*by traels.it*

A formatter that uploads your coverage to a server, that will then host a SVG badge of the score. No need to have the badge stored in repository.

### Build your own

#### [simplecov-erb](https://github.com/kpaulisse/simplecov-erb)
*by [Kevin Paulisse](https://github.com/kpaulisse)*

Flexible formatter that generates the output from an ERB template — the quickest route to a custom format without writing a formatter class.
