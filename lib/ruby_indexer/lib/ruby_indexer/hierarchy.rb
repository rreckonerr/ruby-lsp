# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Hierarchy
    extend T::Sig
    extend T::Generic

    Elem = type_member

    sig { void }
    def initialize
      # Set contaning all elements present in the poset
      @elements = T.let({}, T::Hash[Elem, Node[Elem]])
    end

    sig { params(elem: Elem).returns(Node[Elem]) }
    def add_element(elem)
      node = @elements[elem] ||= Node.new(elem, self)
      node.transitive_from << elem
      node.transitive_to << elem
      node
    end

    sig { params(elem: Elem).returns(T.nilable(Node[Elem])) }
    def [](elem)
      @elements[elem]
    end

    # TODO: There's an issue with sorting still
    # TODO: add lazy_add_relation and incremental_add_relation
    sig { params(from: Elem, to: Elem).void }
    def add_relation(from, to)
      from_node = add_element(from)
      to_node = add_element(to)

      # return if from_node.transitive_to.include?(to)

      from_node.transitive_from.each do |from_elem|
        from_from_node = T.must(@elements[from_elem])

        to_node.transitive_to.each do |to_elem|
          to_to_node = T.must(@elements[to_elem])
          to_to_node.transitive_from << from_elem
          from_from_node.transitive_to << to_elem
        end
      end

      # return if to_node.transitive_to.include?(from)

      to_remove = T.let([], T::Array[Elem])

      to_node.transitive_from.each do |to_elem|
        to_from_node = T.must(@elements[to_elem])

        if to_from_node.transitive_to.include?(from)
          to_remove << to_elem
          # to_from_node.direct_to.delete(to)
        end
      end

      # to_node.direct_from.delete(T.must(to_remove.pop)) until to_remove.empty?

      from_node.direct_to.each do |to_elem|
        from_to_node = T.must(@elements[to_elem])

        if from_to_node.transitive_from.include?(to)
          to_remove << to_elem
          # from_to_node.direct_from.delete(from)
        end
      end

      # from_node.direct_to.delete(T.must(to_remove.pop)) until to_remove.empty?

      from_node.direct_to << to
      to_node.direct_from << from
    end

    class Node
      extend T::Sig
      extend T::Generic

      Elem = type_member

      sig { returns(T::Set[Elem]) }
      attr_reader :direct_from, :transitive_from, :direct_to, :transitive_to

      sig { params(elem: Elem, poset: Hierarchy[Elem]).void }
      def initialize(elem, poset)
        @elem = elem
        @poset = poset
        @direct_from = T.let(Set.new, T::Set[Elem])
        @transitive_from = T.let(Set.new, T::Set[Elem])
        @direct_to = T.let(Set.new, T::Set[Elem])
        @transitive_to = T.let(Set.new, T::Set[Elem])
      end
    end
  end
end

module RubyIndexer
  class Hierarchy2
    extend T::Sig
    extend T::Generic

    Elem = type_member

    sig { void }
    def initialize
      @elements = T.let([], T::Array[Elem])
      @relations = T.let({}, T::Hash[Elem, T::Array[Elem]])
    end

    sig { params(element: Elem).void }
    def add_element(element)
      @elements << element
    end

    sig { params(a: Elem, b: Elem).void }
    def add_relation(a, b)
      @relations[a] ||= []
      T.must(@relations[a]) << b
    end

    sig { returns(T::Hash[Elem, T::Array[Elem]]) }
    def transitive_closure
      closure = {}
      @elements.each do |element|
        closure[element] = []
        stack = [element]
        until stack.empty?
          current = T.must(stack.pop)
          @relations[current]&.each do |related|
            unless closure[element].include?(related)
              closure[element] << related
              stack << related
            end
          end
        end
      end
      closure
    end
  end
end
