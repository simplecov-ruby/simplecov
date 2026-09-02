# frozen_string_literal: true

module SimpleCov
  class TestTracker
    # A one-shot watch that runs a callback the moment a constant of a given name
    # is defined under a host module, via Ruby's `Module#const_added`.
    # `TestTracker` uses it to install the Minitest wrapper in the ordering
    # minitest 6 abandoned plugins for: SimpleCov starts first, as coverage must
    # to see the app load, and minitest is required later, so nothing of
    # minitest's exists yet to hook into.
    #
    # Each watch is its own Module so it can be prepended to the host's singleton
    # class and compose with any `const_added` the host already has. A prepend
    # cannot be removed, so after firing the watch stays in place as a name
    # comparison per constant definition, which is as close to free as Ruby gets.
    class ConstantWatch < Module
      # No `super`: it would forward the implicit block even given explicit
      # arguments, and `Module#initialize` module_evals any block it gets.
      def initialize(name, &on_added)
        @name = name
        @on_added = on_added
        watch = self #: ConstantWatch
        define_method(:const_added) do |added|
          super(added) # steep:ignore UnexpectedPositionalArgument
          watch.notice(added)
        end
      end

      # `host.const_added` runs with the host as self, so reaching this watch's
      # state takes the closure. At runtime the `super` inside is the host's next
      # `const_added`; Steep resolves a define_method block's super against the
      # lexically enclosing method instead.
      def attach(host)
        host.singleton_class.prepend(self)
        self
      end

      def notice(added)
        return unless added.equal?(@name)

        callback = @on_added
        return unless callback

        @on_added = nil
        callback.call
      end
    end
  end
end
