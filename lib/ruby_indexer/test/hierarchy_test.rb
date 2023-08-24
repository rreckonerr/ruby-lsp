# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class HierarchyTest < Minitest::Test
    def test_whatever
      poset = Hierarchy[String].new

      # # Add elements to the set
      # poset.add_element("A")
      # poset.add_element("B")
      # poset.add_element("C")
      # poset.add_element("D")
      # poset.add_element("E")
      # poset.add_element("C*")

      # Add relations between elements
      poset.add_relation("A", "B")
      poset.add_relation("C", "D")
      poset.add_relation("D", "E")
      poset.add_relation("A", "D")
      poset.add_relation("A", "C")
      poset.add_relation("B", "C")

      ["A", "B", "C", "D", "E"].each do |elem|
        node = T.must(poset[elem])
        puts elem
        puts("Direct to " + node.direct_to.join(","))
        puts("Transitive to " + node.transitive_to.join(","))
        puts("Direct from " + node.direct_from.join(","))
        puts("Transitive from " + node.transitive_from.join(","))
        puts "\n"
      end

      poset = Hierarchy2[String].new

      # # Add elements to the set
      poset.add_element("D")
      poset.add_element("E")
      poset.add_element("A")
      poset.add_element("B")
      poset.add_element("C")

      # Add relations between elements
      poset.add_relation("A", "B")
      poset.add_relation("C", "D")
      poset.add_relation("D", "E")
      poset.add_relation("A", "D")
      poset.add_relation("A", "C")
      poset.add_relation("B", "C")

      puts poset.transitive_closure
    end
  end
end
