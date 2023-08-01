# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Selection ranges demo](../../selection_ranges.gif)
    #
    # The [selection ranges](https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange)
    # request informs the editor of ranges that the user may want to select based on the location(s)
    # of their cursor(s).
    #
    # Trigger this request with: Ctrl + Shift + -> or Ctrl + Shift + <-
    #
    # Note that if using VSCode Neovim, you will need to be in Insert mode for this to work correctly.
    #
    # # Example
    #
    # ```ruby
    # def foo # --> The next selection range encompasses the entire method definition.
    #   puts "Hello, world!" # --> Cursor is on this line
    # end
    # ```
    class SelectionRanges < BaseRequest
      extend T::Sig

      NODES_THAT_CAN_BE_PARENTS = T.let(
        [
          # YARP::AssignNode,
          YARP::ArrayNode,
          YARP::BeginNode,
          YARP::BlockNode,
          YARP::CallNode,
          YARP::CaseNode,
          YARP::ClassNode,
          # YARP::Comment, # not a YARP::Node
          YARP::DefNode,
          YARP::ElseNode,
          YARP::EnsureNode,
          YARP::ForNode,
          YARP::HashNode,
          # YARP::HeredocNode,
          # YARP::HeredocBegNode,
          YARP::HashPatternNode,
          YARP::IfNode,
          YARP::InNode,
          YARP::LambdaNode,
          YARP::ModuleNode,
          YARP::ParametersNode,
          YARP::RescueNode,
          # YARP::RescueExNode
          YARP::StringConcatNode,
          #YARP::StringLiteralNode,
          YARP::UnlessNode,
          YARP::UntilNode,
          YARP::WhenNode,
          YARP::WhileNode
        ].freeze,
        T::Array[T.class_of(YARP::Node)]
      )

      sig { params(document: Document).void }
      def initialize(document)
        super(document)

        @ranges = T.let([], T::Array[Support::SelectionRange])
        @stack = T.let([], T::Array[Support::SelectionRange])
      end

      sig { override.returns(T.all(T::Array[Support::SelectionRange], Object)) }
      def run
        visit(@document.tree)
        @ranges.reverse!
      end

      private

      sig { override.params(node: T.nilable(YARP::Node)).void }
      def visit(node)
        return if node.nil?

        range = create_selection_range(node.location, @stack.last)

        @ranges << range
        return if node.child_nodes.empty?

        @stack << range if NODES_THAT_CAN_BE_PARENTS.include?(node.class)
        visit_all(node.child_nodes)
        @stack.pop if NODES_THAT_CAN_BE_PARENTS.include?(node.class)
      end

      sig do
        params(
          location: YARP::Location,
          parent: T.nilable(Support::SelectionRange),
        ).returns(Support::SelectionRange)
      end
      def create_selection_range(location, parent = nil)
        RubyLsp::Requests::Support::SelectionRange.new(
          range: Interface::Range.new(
            start: Interface::Position.new(
              line: location.start_line - 1,
              character: location.start_column,
            ),
            end: Interface::Position.new(
              line: location.end_line - 1,
              character: location.end_column,
            ),
          ),
          parent: parent,
        )
      end
    end
  end
end
