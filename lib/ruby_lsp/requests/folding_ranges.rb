# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Folding ranges demo](../../folding_ranges.gif)
    #
    # The [folding ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_foldingRange)
    # request informs the editor of the ranges where and how code can be folded.
    #
    # # Example
    #
    # ```ruby
    # def say_hello # <-- folding range start
    #   puts "Hello"
    # end # <-- folding range end
    # ```
    class FoldingRanges < BaseRequest
      extend T::Sig

      SIMPLE_FOLDABLES = T.let(
        [
          YARP::ArrayNode,
          YARP::BlockNode,
          YARP::CaseNode,
          YARP::ClassNode,
          YARP::ForNode,
          YARP::HashNode,
          YARP::InterpolatedStringNode,
          YARP::ModuleNode,
          YARP::SingletonClassNode,
          YARP::UnlessNode,
          YARP::UntilNode,
          YARP::WhileNode,
          YARP::ElseNode,
          YARP::EnsureNode,
          YARP::BeginNode,
        ].freeze,
        T::Array[T.class_of(YARP::Node)],
      )

      NODES_WITH_STATEMENTS = T.let(
        [
          YARP::IfNode,
          # YARP::InNode,
          YARP::RescueNode,
          YARP::WhenNode,
        ].freeze,
        T::Array[T.class_of(YARP::Node)],
      )

      StatementNode = T.type_alias do
        T.any(
          YARP::IfNode,
          YARP::InNode,
          YARP::RescueNode,
          YARP::WhenNode,
        )
      end

      sig { params(document: Document).void }
      def initialize(document)
        super

        @ranges = T.let([], T::Array[Interface::FoldingRange])
        @partial_range = T.let(nil, T.nilable(PartialRange))
      end

      sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      def run
        visit(@document.tree)
        emit_partial_range

        @ranges
      end

      private

      sig { override.params(node: T.nilable(YARP::Node)).void }
      def visit(node)
        return unless handle_partial_range(node)

        case node
        when *SIMPLE_FOLDABLES
          if node.is_a?(YARP::BeginNode) && node.rescue_clause
            add_lines_range(node.rescue_clause.location.start_line, node.location.end_line - 1)
          else
            location = T.must(node).location
            add_lines_range(location.start_line, location.end_line - 1)
          end
        when *NODES_WITH_STATEMENTS
          x = T.cast(node, StatementNode).statements
          add_statements_range(T.must(node), x) if x
        when YARP::CallNode
          # If there is a receiver, it may be a chained invocation,
          # so we need to process it in special way.
          # debugger
          # unless node.block && node.location.start_line == node.block.location.start_line
          unless same_lines_for_call_and_block?(node)
            if node.receiver.nil?
              location = node.location
              add_lines_range(location.start_line, location.end_line - 1)
            else
              add_call_range(node)
              return
            end
          end
        # when SyntaxTree::Command
        #   unless same_lines_for_command_and_block?(node)
        #     location = node.location
        #     add_lines_range(location.start_line, location.end_line - 1)
        #   end
        when YARP::DefNode
          debugger
          add_def_range(node)
        when YARP::StringConcatNode
          add_string_concat(node)
          return
        end

        super
      end

      # This is to prevent duplicate ranges
      sig { params(node: YARP::CallNode).returns(T::Boolean) }
      def same_lines_for_call_and_block?(node)
        node_block = node.block
        return false unless node_block

        location = node.location
        block_location = node_block.location
        block_location.start_line == location.start_line && block_location.end_line == location.end_line
      end

      class PartialRange
        extend T::Sig

        sig { returns(String) }
        attr_reader :kind

        sig { returns(Integer) }
        attr_reader :end_line

        class << self
          extend T::Sig

          sig { params(node: YARP::Node, kind: String).returns(PartialRange) }
          def from(node, kind)
            new(node.location.start_line - 1, node.location.end_line - 1, kind)
          end
        end

        sig { params(start_line: Integer, end_line: Integer, kind: String).void }
        def initialize(start_line, end_line, kind)
          @start_line = start_line
          @end_line = end_line
          @kind = kind
        end

        sig { params(node: YARP::Node).returns(PartialRange) }
        def extend_to(node)
          @end_line = node.location.end_line - 1
          self
        end

        sig { params(node: YARP::Node).returns(T::Boolean) }
        def new_section?(node)
          false
          # node.is_a?(SyntaxTree::Comment) && @end_line + 1 != node.location.start_line - 1
        end

        sig { returns(Interface::FoldingRange) }
        def to_range
          Interface::FoldingRange.new(
            start_line: @start_line,
            end_line: @end_line,
            kind: @kind,
          )
        end

        sig { returns(T::Boolean) }
        def multiline?
          @end_line > @start_line
        end
      end

      sig { params(node: T.nilable(YARP::Node)).returns(T::Boolean) }
      def handle_partial_range(node)
        kind = partial_range_kind(node)

        if kind.nil?
          emit_partial_range
          return true
        end

        target_node = T.must(node)
        @partial_range = if @partial_range.nil?
          PartialRange.from(target_node, kind)
        elsif @partial_range.kind != kind || @partial_range.new_section?(target_node)
          emit_partial_range
          PartialRange.from(target_node, kind)
        else
          @partial_range.extend_to(target_node)
        end

        false
      end

      sig { params(node: T.nilable(YARP::Node)).returns(T.nilable(String)) }
      def partial_range_kind(node)
        case node
        # when SyntaxTree::Comment
        #   "comment"
        when YARP::CallNode
          if node.message == "require" || node.message == "require_relative"
            "imports"
          end
        end
      end

      sig { void }
      def emit_partial_range
        return if @partial_range.nil?

        @ranges << @partial_range.to_range if @partial_range.multiline?
        @partial_range = nil
      end

      sig { params(node: YARP::CallNode).void }
      def add_call_range(node)
        receiver = T.let(node.receiver, T.nilable(YARP::Node))

        while receiver.is_a?(YARP::CallNode)
          visit(receiver.arguments)
          receiver = receiver.receiver

          if receiver
            add_lines_range(
              receiver.location.start_line - 1,
              node.location.end_line - 1,
            )
          end
        end

        visit(node.block)
      end

      sig { params(node: YARP::DefNode).void }
      def add_def_range(node)
        # For an endless method with no arguments, `node.params` returns `nil` for Ruby 3.0, but a `Syntax::Params`
        # for Ruby 3.1
        params = node.parameters
        # debugger
        # return unless params

        # params_location = params.location
        # debugger
        return unless node.statements

        # if params_location.start_line < params_location.end_line
          # debugger
        #   add_lines_range(params_location.start_line, node.location.end_line - 1)
        # else
        # debugger
          # location = node.location
          # add_lines_range(location.start_line, location.end_line - 1)
          add_lines_range(node.statements.location.start_line - 1, node.statements.location.end_line)
        # end

        visit(node.statements)
      end

      sig { params(node: YARP::Node, statements: YARP::StatementsNode).void }
      def add_statements_range(node, statements)
        return if statements.child_nodes.empty?

        add_lines_range(node.location.start_line, statements.body.last.location.end_line)
      end

      sig { params(node: YARP::StringConcatNode).void }
      def add_string_concat(node)
        left = T.let(node.left, YARP::Node)
        left = left.left while left.is_a?(YARP::StringConcatNode)

        add_lines_range(left.location.start_line, node.right.location.end_line - 1)
      end

      sig { params(start_line: Integer, end_line: Integer).void }
      def add_lines_range(start_line, end_line)
        return if start_line >= end_line

        @ranges << Interface::FoldingRange.new(
          start_line: start_line - 1,
          end_line: end_line - 1,
          kind: "region",
        )
      end
    end
  end
end
