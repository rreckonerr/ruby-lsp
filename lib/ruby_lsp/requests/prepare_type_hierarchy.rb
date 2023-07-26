# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class PrepareTypeHierarchy < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(T::Array[Interface::TypeHierarchyItem]) } }

      # ALLOWED_TARGETS = T.let(
      #   [
      #     SyntaxTree::Command,
      #     SyntaxTree::CallNode,
      #     SyntaxTree::ConstPathRef,
      #   ],
      #   T::Array[T.class_of(SyntaxTree::Node)],
      # )

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig do
        params(
          emitter: EventEmitter,
          message_queue: Thread::Queue,
          document: Document,
          target: SyntaxTree::Node,
        ).void
      end
      def initialize(emitter, message_queue, document, target)
        super(emitter, message_queue)

        @document = document
        @target = target
        @external_listeners = T.let([], T::Array[RubyLsp::Listener[ResponseType]])
        @response = T.let(nil, ResponseType)
        $stderr.puts "REGISTER"
        emitter.register(self, :on_class, :after_class, :on_module, :after_module)
        @stack = T.let([], T::Array[String])

        register_external_listeners!
      end

      sig { void }
      def register_external_listeners!
        self.class.listeners.each do |l|
          @external_listeners << T.unsafe(l).new(@emitter, @message_queue)
        end
      end

      sig { void }
      def merge_external_listeners_responses!
        @external_listeners.each do |l|
          merge_response!(l)
        end
      end

      # Merges responses from other hover listeners
      sig { params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        other_response = other.response
        return self unless other_response

        if @response.nil?
          @response = other.response
        else
          @response.concat(other_response)
        end

        self
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def on_class(node)
        $stderr.puts "ON_CLASS: #{node}"

        @stack << full_constant_name(node.constant)
        return unless @target == node

        @response = [
          Interface::TypeHierarchyItem.new(
            name: full_name,
            kind: Constant::SymbolKind::CLASS,
            uri: @document.uri,
            range: range_from_syntax_tree_node(node),
            selection_range: range_from_syntax_tree_node(node.constant),
          ),
        ]
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def after_class(node)
        @stack.pop
      end

      sig { params(node: SyntaxTree::ModuleDeclaration).void }
      def on_module(node)
        $stderr.puts "ON_MODULE: #{node}"

        @stack << full_constant_name(node.constant)
        return unless @target == node

        @response = [
          Interface::TypeHierarchyItem.new(
            name: full_name,
            kind: Constant::SymbolKind::MODULE,
            uri: @document.uri,
            range: range_from_syntax_tree_node(node),
            selection_range: range_from_syntax_tree_node(node.constant),
          ),
        ]
      end

      sig { params(node: SyntaxTree::ModuleDeclaration).void }
      def after_module(node)
        @stack.pop
      end

      # sig { params(node: SyntaxTree::ConstPathRef).void }
      # def on_const_path_ref(node)
      #   @response = []
      # end

      private

      sig { returns(String) }
      def full_name
        @stack.join("::")
      end

      # sig { params(name: String, node: SyntaxTree::Node).returns(T.nilable(Interface::Hover)) }
      # def type_hierarchy(name, node)
      #   urls = Support::RailsDocumentClient.generate_rails_document_urls(name)
      #   return if urls.empty?

      #   contents = Interface::MarkupContent.new(kind: "markdown", value: urls.join("\n\n"))
      #   Interface::Hover.new(range: range_from_syntax_tree_node(node), contents: contents)
      # end
    end
  end
end
