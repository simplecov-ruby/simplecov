# frozen_string_literal: true

require "helper"

RSpec.describe SimpleCov::TestTracker::MethodBodies do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def masks_of(name, source)
    path = File.join(dir, name)
    File.write(path, source)
    described_class.masks(path)
  end

  context "with a Ruby file", :prism do
    let(:source) do
      <<~RUBY
        class Thing
          def call
            :called
          end
          def one; two; end; def other = (c || d)
          def outer
            def inner = (e || f)
            def nested
              :nested
            end
          end
          def noop
          end
        end
      RUBY
    end

    it "marks method body lines, and the lines of one-line methods" do
      expect(masks_of("thing.rb", source).map { |mask| mask.to_s(2) }).to eq(%w[1111000100 1010000])
    end

    it "counts every line, and no one-line method, without Prism" do
      allow(SimpleCov::StaticCoverageExtractor).to receive(:prism_loaded?).and_return(false)

      expect(masks_of("thing.rb", source)).to eq([described_class::EVERY_LINE, 0])
    end
  end

  it "counts every line, and no one-line method, in a file that is not Ruby" do
    expect(masks_of("card.html.erb", "<%= 1 %>\n")).to eq([described_class::EVERY_LINE, 0])
  end

  it "counts every line, and no one-line method, in a file it cannot read" do
    expect(described_class.masks(File.join(dir, "gone.rb"))).to eq([described_class::EVERY_LINE, 0])
  end
end
