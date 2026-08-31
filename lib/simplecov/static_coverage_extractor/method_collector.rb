# frozen_string_literal: true

module SimpleCov
  module StaticCoverageExtractor
    # Visitor mixin that collects method tuples and tracks the lexical class /
    # module nesting that names them, in the shape Ruby's `Coverage` reports
    # methods. Module and Class are both namespaces here, since `Coverage` reports
    # both as the constant.
    module MethodCollector
      def visit_class_node(node)
        with_class(constant_name(node.constant_path)) { super }
      end

      def visit_module_node(node)
        with_class(constant_name(node.constant_path)) { super }
      end

      # `def name(...)` and `def self.name(...)` both produce DefNode. The class
      # context is the surrounding lexical class or module, or `Object` at the top
      # level, matching `Coverage`'s convention. Suppression covers 3.2's folded
      # dead arms, where nested branches stay instrumented but a `def` never
      # registers.
      def visit_def_node(node)
        return super if @suppress_methods

        class_name = @class_stack.last || "Object"
        key = [class_name, node.name, node.start_line, node.start_column, node.end_line, node.end_column]
        @methods[key] = 0
        super
      end

    private

      def constant_name(node)
        return "<anonymous>" if node.nil?
        return node.slice if node.respond_to?(:slice)

        node.to_s
      end

      def with_class(name)
        @class_stack.push(name)
        yield
      ensure
        @class_stack.pop
      end
    end
  end
end
