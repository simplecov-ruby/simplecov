# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # Visitor mixin that collects method tuples and tracks the lexical
    # class / module nesting that names them, in the shape Ruby's
    # `Coverage` reports methods. Mixed into `Visitor`, it shares that
    # visitor's `@methods` / `@class_stack` state and keeps the
    # method-collection concern separate from branch extraction.
    module MethodCollector
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

      # Render a constant path (e.g., `Foo::Bar`) as its source-form
      # string. Defensive nil / to_s fallbacks: ClassNode and ModuleNode
      # always carry a constant_path in practice.
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
