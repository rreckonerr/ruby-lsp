# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class TypeHierarchySubtypes < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(T::Array[Interface::TypeHierarchyItem]) } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue, item: Interface::TypeHierarchyItem).void }
      def initialize(emitter, message_queue, item)
        super(emitter, message_queue)

        @item = item
        @external_listeners = T.let([], T::Array[RubyLsp::Listener[ResponseType]])
        @response = T.let(nil, ResponseType)

        register_external_listeners!
      end

      sig { void }
      def register_external_listeners!
        self.class.listeners.each do |l|
          @external_listeners << T.unsafe(l).new(@emitter, @message_queue, @item)
        end
      end

      sig { void }
      def merge_external_listeners_responses!
        @external_listeners.each do |l|
          merge_response!(l)
        end
      end

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
    end
  end
end
