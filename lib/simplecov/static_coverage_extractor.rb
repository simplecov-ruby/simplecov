# frozen_string_literal: true

require "set"

begin
  require "prism"
rescue LoadError
  # Prism isn't available on this Ruby (older than 3.3 without the gem).
  # `StaticCoverageExtractor.available?` will return false and callers
  # fall back to the previous "empty hashes" behavior.
end

module SimpleCov
  # Static enumeration of the branches and methods Ruby's `Coverage` library
  # WOULD have reported if a file had been loaded with `branches: true` /
  # `methods: true`. Used by `SimulateCoverage` to backfill data for files
  # added via `cover` / `track_files` that were never `require`'d during the
  # run — so unloaded files contribute to the branch/method denominators
  # symmetrically with their line coverage, instead of vanishing from the
  # totals (see #1059).
  #
  # Implementation uses Prism (stdlib in Ruby 3.3+, gem on older Rubies).
  # When Prism isn't available, `available?` returns false and SimulateCoverage
  # falls back to the previous behavior — older Rubies keep working, just
  # without the synthesized data.
  #
  # The emitted shape mirrors `Coverage.result[path]` for the same file:
  # branches are nested as `{condition_tuple => {arm_tuple => 0, ...}}` and
  # methods as `{["ClassName", :name, lines/cols] => 0}`. Position info
  # comes from Prism's reported source locations; it doesn't always match
  # `Coverage`'s byte-for-byte (the two parsers report slightly different
  # column conventions for some constructs), but lines are reliable and
  # downstream consumers that key off line numbers (the HTML formatter,
  # SonarQube, etc.) see the data they expect.
  module StaticCoverageExtractor
  module_function

    # simplecov:disable branch
    # The Prism-unavailable arm of this ternary is unreachable when Prism
    # itself IS loadable — i.e., on every engine that exercises the dogfood
    # report. Asserted-on by callers; tested indirectly via the
    # `available?`-returns-false fallback path in SimulateCoverage's spec.
    def available?
      defined?(::Prism) ? true : false
    end
    # simplecov:enable branch

    # Parse `source` (a string of Ruby) and return a hash of the form
    # `{"branches" => {...}, "methods" => {...}}` matching the shape that
    # `Coverage.result[path]` produces. Returns nil on parse failure or
    # when Prism isn't available; callers should treat that as "couldn't
    # extract — fall back to empty hashes."
    def call(source)
      # simplecov:disable branch — `then` arm unreachable when Prism IS loadable
      return nil unless available?

      # simplecov:enable branch

      result = ::Prism.parse(source)
      return nil if result.failure?

      visitor = Visitor.new
      visitor.visit(result.value)
      {"branches" => visitor.branches, "methods" => visitor.methods}
    rescue StandardError
      # simplecov:disable line
      # Parser errors beyond the .failure? check, unsupported AST shapes,
      # or anything else: fall back to empty hashes rather than crashing
      # the whole report. Defensive; hard to trigger from a real source
      # input that Prism accepts at parse time.
      nil
      # simplecov:enable line
    end

    # Summarize a source file's REAL branch and method positions, for the
    # `:eval_generated` filter (SimpleCov.ignore_branches /
    # SimpleCov.ignore_methods, #1046). Returns a hash:
    #
    #   {
    #     branches: Set[start_line, ...],         # e.g., [3, 12, 20]
    #     methods:  Set[[name, start_line], ...]  # e.g., [[:foo, 7], [:bar, 13]]
    #   }
    #
    # Branch matching is start_line-only because Coverage's condition type
    # vocabulary (`:if`, `:unless`, `:case`, `:while`, `:until`) does not
    # always match Prism's emitted type (the existing visitor reports
    # `:if` for `unless` and ternary). Coincidental line-sharing between
    # a real branch and an eval-generated one will keep both, which is
    # an acceptable false-negative for an opt-in filter. Method matching
    # uses (name, start_line) since a method name is unique at any line.
    #
    # Returns nil when Prism is unavailable or parsing fails, signaling
    # callers to keep every Coverage entry (no false drops).
    def real_source_positions(source)
      extracted = call(source)
      return nil unless extracted

      {
        branches: extracted["branches"].keys.to_set { |tuple| tuple[2] },
        methods: extracted["methods"].keys.to_set { |tuple| [tuple[1], tuple[2]] }
      }
    end

    # simplecov:disable branch
    # The `else` arm (Prism missing) is unreachable on engines where the
    # dogfood report runs; the Visitor class only matters when Prism is
    # loadable.
    if available?
      # simplecov:enable branch

      # `Prism::IfNode#subsequent` was renamed from `consequent` in Prism
      # 1.3 (Dec 2024). Ruby 3.3's stdlib still ships an older Prism that
      # only exposes `consequent`; 3.4+ and any project that's done
      # `gem install prism` exposes `subsequent`. Resolve the method name
      # ONCE here so the per-node hot path stays branch-free. The
      # not-taken arm on whichever Prism version we're on can't be
      # exercised by our own dogfood (we only run on one Prism at a time).
      # simplecov:disable
      IF_NODE_SUBSEQUENT_METHOD =
        if ::Prism::IfNode.method_defined?(:subsequent)
          :subsequent
        else
          :consequent
        end
      # simplecov:enable
      # Prism visitor that accumulates branch and method tuples in the
      # shape Ruby's `Coverage` reports. Tuple ids are sequential across
      # the file — `Coverage` uses sequential ids too, so this matches the
      # conventional shape. Only defined when Prism is loadable;
      # `available?` is the runtime gate.
      class Visitor < ::Prism::Visitor
        attr_reader :branches, :methods

        def initialize
          super
          @branches = {}
          @methods = {}
          @next_id = 0
          @class_stack = []
        end

        # `if` / `unless` / postfix-if / postfix-unless / ternary all parse
        # as IfNode (or UnlessNode). Both carry a `then` arm (the
        # statements body) and an optional `subsequent` (an ElseNode for
        # `else`, another IfNode for `elsif`). When the subsequent is
        # missing, Coverage synthesizes a `:else` arm attributed to the
        # whole condition's range — we do the same.
        def visit_if_node(node)
          emit_if_like(node)
          super
        end

        def visit_unless_node(node)
          emit_if_like(node)
          super
        end

        # `case`/`when` and `case`/`in` (pattern matching) parse as CaseNode
        # and CaseMatchNode respectively. When there's no explicit `else`,
        # Coverage synthesizes one at the case's range.
        def visit_case_node(node)
          emit_case_like(node, :when)
          super
        end

        def visit_case_match_node(node)
          emit_case_like(node, :in)
          super
        end

        # `while` / `until` loops get a single `:body` arm. No synthetic
        # else (the loop either runs the body or doesn't).
        def visit_while_node(node)
          emit_loop(node, :while)
          super
        end

        def visit_until_node(node)
          emit_loop(node, :until)
          super
        end

        # Track class/module nesting so method tuples carry the lexical
        # class name. Module + Class are both treated as namespaces here
        # since `Coverage` reports both as the constant.
        def visit_class_node(node)
          with_class(constant_name(node.constant_path)) { super }
        end

        def visit_module_node(node)
          with_class(constant_name(node.constant_path)) { super }
        end

        # `def name(...)` and `def self.name(...)` both produce DefNode.
        # The class context is the surrounding lexical class/module (or
        # `Object` at the top level, matching `Coverage`'s convention).
        def visit_def_node(node)
          loc = node.location
          class_name = @class_stack.last || "Object"
          key = [class_name, node.name, loc.start_line, loc.start_column, loc.end_line, loc.end_column]
          @methods[key] = 0
          super
        end

      private

        # IfNode and UnlessNode are the same structural shape (predicate +
        # then body + optional else/elsif), but they use different
        # accessors: IfNode#subsequent (or #consequent on older Prism —
        # see IF_NODE_SUBSEQUENT_METHOD above), which can be either an
        # ElseNode for `else` or another IfNode for `elsif`;
        # UnlessNode#else_clause (always an ElseNode, since `elsif` after
        # `unless` isn't valid syntax). Treat them uniformly through
        # `if_like_else_location`.
        def emit_if_like(node)
          then_loc = arm_location(node.statements, node.location)
          else_loc = if_like_else_location(node)
          @branches[build_tuple(:if, node.location)] = {
            build_tuple(:then, then_loc) => 0,
            build_tuple(:else, else_loc) => 0
          }
        end

        # Resolve the source range Coverage attributes to a real-or-synthetic
        # `:else` arm of an if-like construct. IfNode uses
        # `subsequent` / `consequent` depending on Prism version (resolved
        # to `IF_NODE_SUBSEQUENT_METHOD` at load time); UnlessNode uses
        # `else_clause`. When neither is present, the synthesized else
        # inherits the whole condition's range (matches Coverage's
        # convention).
        def if_like_else_location(node)
          sub = if node.is_a?(::Prism::IfNode)
                  node.public_send(IF_NODE_SUBSEQUENT_METHOD)
                else
                  node.else_clause
                end
          return node.location unless sub

          arm_location(else_body_of(sub), sub.location)
        end

        def emit_case_like(node, when_type)
          arms = node.conditions.to_h do |when_node|
            loc = arm_location(when_node.statements, when_node.location)
            [build_tuple(when_type, loc), 0]
          end
          arms[build_tuple(:else, else_arm_location(node))] = 0
          @branches[build_tuple(:case, node.location)] = arms
        end

        # Resolve the source range Coverage attributes to a synthetic-or-real
        # `:else` arm of a case construct: the body of an explicit else,
        # or the case's full range when no else is present.
        def else_arm_location(node)
          return node.location unless node.else_clause

          arm_location(else_body_of(node.else_clause), node.else_clause.location)
        end

        def emit_loop(node, type)
          cond_tuple = build_tuple(type, node.location)
          body_loc = arm_location(node.statements, node.location)
          @branches[cond_tuple] = {build_tuple(:body, body_loc) => 0}
        end

        # Body location for an arm. Prism's `statements` is a
        # StatementsNode containing one or more expressions; the location
        # of the StatementsNode itself spans them. When the arm body is
        # empty (e.g., `if cond then end`), fall back to the parent's
        # location so we always have a usable tuple.
        def arm_location(statements, fallback_location)
          statements&.location || fallback_location
        end

        # simplecov:disable branch
        # The `else_node` fallback is defensive: every Prism node passed
        # in here in practice responds to `:statements`.
        # ElseNode wraps a `statements` body. We want the body's location,
        # not the `else` keyword + body span — Coverage reports the body.
        def else_body_of(else_node)
          else_node.respond_to?(:statements) ? else_node.statements : else_node
        end
        # simplecov:enable branch

        def build_tuple(type, location)
          id = @next_id
          @next_id += 1
          [type, id, location.start_line, location.start_column, location.end_line, location.end_column]
        end

        # Render a constant path (e.g., `Foo::Bar`) as its source-form
        # string. Coverage uses the actual Class constant in the live case;
        # since we're not loading the file we approximate with the string.
        # The nil-check and to_s fallback are defensive: ClassNode and
        # ModuleNode always carry a constant_path, and every Prism node
        # responds to `slice`.
        # simplecov:disable
        def constant_name(node)
          return "<anonymous>" if node.nil?
          return node.slice if node.respond_to?(:slice)

          node.to_s
        end
        # simplecov:enable

        def with_class(name)
          @class_stack.push(name)
          yield
        ensure
          @class_stack.pop
        end
      end
    end
  end
end
