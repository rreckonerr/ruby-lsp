# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Index
    extend T::Sig

    # The minimum Jaro-Winkler similarity score for an entry to be considered a match for a given fuzzy search query
    ENTRY_SIMILARITY_THRESHOLD = 0.7

    # A type representing the structure of the cached index, returning the instance variables in an array:
    # [@entries, @entries_tree, @files_to_entries, @require_paths_tree]
    MarshalCacheType = T.type_alias do
      [
        T::Hash[String, T::Array[Entry]],
        PrefixTree[T::Array[Entry]],
        T::Hash[String, T::Array[Entry]],
        PrefixTree[IndexablePath],
      ]
    end

    # class << self
    #   extend T::Sig

    #   sig { params(tuple: MarshalCacheType).returns(Index) }
    #   def _load(tuple)
    #     Index.new(*tuple)
    #   end
    # end

    sig { returns(T::Hash[String, T::Array[Entry]]) }
    attr_reader :entries

    sig { returns(PrefixTree[T::Array[Entry]]) }
    attr_reader :entries_tree

    sig { returns(T::Hash[String, T::Array[Entry]]) }
    attr_reader :files_to_entries

    sig { returns(PrefixTree[IndexablePath]) }
    attr_reader :require_paths_tree

    sig do
      params(
        entries: T::Hash[String, T::Array[Entry]],
        entries_tree: PrefixTree[T::Array[Entry]],
        files_to_entries: T::Hash[String, T::Array[Entry]],
        require_paths_tree: PrefixTree[IndexablePath],
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      entries = {},
      entries_tree = PrefixTree[T::Array[Entry]].new,
      files_to_entries = {},
      require_paths_tree = PrefixTree[IndexablePath].new
    )
      # Holds all entries in the index using the following format:
      # {
      #  "Foo" => [#<Entry::Class>, #<Entry::Class>],
      #  "Foo::Bar" => [#<Entry::Class>],
      # }
      @entries = entries

      # Holds all entries in the index using a prefix tree for searching based on prefixes to provide autocompletion
      @entries_tree = entries_tree

      # Holds references to where entries where discovered so that we can easily delete them
      # {
      #  "/my/project/foo.rb" => [#<Entry::Class>, #<Entry::Class>],
      #  "/my/project/bar.rb" => [#<Entry::Class>],
      # }
      @files_to_entries = files_to_entries

      # Holds all require paths for every indexed item so that we can provide autocomplete for requires
      @require_paths_tree = require_paths_tree
    end

    sig { params(indexable: IndexablePath).void }
    def delete(indexable)
      # For each constant discovered in `path`, delete the associated entry from the index. If there are no entries
      # left, delete the constant from the index.
      @files_to_entries[indexable.full_path]&.each do |entry|
        name = entry.name
        entries = @entries[name]
        next unless entries

        # Delete the specific entry from the list for this name
        entries.delete(entry)

        # If all entries were deleted, then remove the name from the hash and from the prefix tree. Otherwise, update
        # the prefix tree with the current entries
        if entries.empty?
          @entries.delete(name)
          @entries_tree.delete(name)
        else
          @entries_tree.insert(name, entries)
        end
      end

      @files_to_entries.delete(indexable.full_path)

      require_path = indexable.require_path
      @require_paths_tree.delete(require_path) if require_path
    end

    sig { params(entry: Entry).void }
    def <<(entry)
      name = entry.name

      (@entries[name] ||= []) << entry
      (@files_to_entries[entry.file_path] ||= []) << entry
      @entries_tree.insert(name, T.must(@entries[name]))
    end

    sig { params(fully_qualified_name: String).returns(T.nilable(T::Array[Entry])) }
    def [](fully_qualified_name)
      @entries[fully_qualified_name.delete_prefix("::")]
    end

    sig { params(query: String).returns(T::Array[IndexablePath]) }
    def search_require_paths(query)
      @require_paths_tree.search(query)
    end

    # Searches entries in the index based on an exact prefix, intended for providing autocomplete. All possible matches
    # to the prefix are returned. The return is an array of arrays, where each entry is the array of entries for a given
    # name match. For example:
    # ## Example
    # ```ruby
    # # If the index has two entries for `Foo::Bar` and one for `Foo::Baz`, then:
    # index.prefix_search("Foo::B")
    # # Will return:
    # [
    #   [#<Entry::Class name="Foo::Bar">, #<Entry::Class name="Foo::Bar">],
    #   [#<Entry::Class name="Foo::Baz">],
    # ]
    # ```
    sig { params(query: String, nesting: T::Array[String]).returns(T::Array[T::Array[Entry]]) }
    def prefix_search(query, nesting)
      results = (nesting.length + 1).downto(0).flat_map do |i|
        prefix = T.must(nesting[0...i]).join("::")
        namespaced_query = prefix.empty? ? query : "#{prefix}::#{query}"
        @entries_tree.search(namespaced_query)
      end

      results.uniq!
      results
    end

    # Fuzzy searches index entries based on Jaro-Winkler similarity. If no query is provided, all entries are returned
    sig { params(query: T.nilable(String)).returns(T::Array[Entry]) }
    def fuzzy_search(query)
      return @entries.flat_map { |_name, entries| entries } unless query

      normalized_query = query.gsub("::", "").downcase

      results = @entries.filter_map do |name, entries|
        similarity = DidYouMean::JaroWinkler.distance(name.gsub("::", "").downcase, normalized_query)
        [entries, -similarity] if similarity > ENTRY_SIMILARITY_THRESHOLD
      end
      results.sort_by!(&:last)
      results.flat_map(&:first)
    end

    # Try to find the entry based on the nesting from the most specific to the least specific. For example, if we have
    # the nesting as ["Foo", "Bar"] and the name as "Baz", we will try to find it in this order:
    # 1. Foo::Bar::Baz
    # 2. Foo::Baz
    # 3. Baz
    sig { params(name: String, nesting: T::Array[String]).returns(T.nilable(T::Array[Entry])) }
    def resolve(name, nesting)
      (nesting.length + 1).downto(0).each do |i|
        prefix = T.must(nesting[0...i]).join("::")
        full_name = prefix.empty? ? name : "#{prefix}::#{name}"
        entries = @entries[full_name]
        return entries if entries
      end

      nil
    end

    sig { params(indexable_paths: T::Array[IndexablePath]).void }
    def index_all(indexable_paths: RubyIndexer.configuration.indexables)
      cache_path = RubyIndexer.configuration.cache_path
      FileUtils.mkdir_p(cache_path) unless Dir.exist?(cache_path)

      ignore_path = File.join(cache_path, ".gitignore")
      File.write(ignore_path, "*") unless File.exist?(ignore_path)

      grouped_paths = indexable_paths.group_by(&:gem_name)
      non_gem_paths = grouped_paths.delete(nil) || []

      gem_indices = grouped_paths.map do |_gem_name, indexable_paths|
        first_path = T.must(indexable_paths.first)
        gem_cache = File.join(cache_path, first_path.cache_file_name)

        if File.exist?(gem_cache)
          # Load the index from the cache
          T.cast(Marshal.load(File.read(gem_cache)), Index)
        else
          # Index the gem and cache it for future runs
          index = Index.new
          indexable_paths.each { |ip| index.index_single(ip) }

          File.write(gem_cache, Marshal.dump(index))
          index
        end
      end

      gem_indices.each { |index| merge!(index) }
      non_gem_paths.each { |path| index_single(path) }
    end

    sig { params(indexable_path: IndexablePath, source: T.nilable(String)).void }
    def index_single(indexable_path, source = nil)
      content = source || File.read(indexable_path.full_path)
      visitor = IndexVisitor.new(self, YARP.parse(content), indexable_path.full_path)
      visitor.run

      require_path = indexable_path.require_path
      @require_paths_tree.insert(require_path, indexable_path) if require_path
    rescue Errno::EISDIR
      # If `path` is a directory, just ignore it and continue indexing
    end

    # sig { params(level: T.untyped).returns(MarshalCacheType) }
    # def _dump(level)
    #   [@entries, @entries_tree, @files_to_entries, @require_paths_tree]
    # end

    sig { returns(MarshalCacheType) }
    def marshal_dump
      [@entries, @entries_tree, @files_to_entries, @require_paths_tree]
    end

    sig { params(cache: MarshalCacheType).void }
    def marshal_load(cache)
      @entries, @entries_tree, @files_to_entries, @require_paths_tree = cache
    end

    sig { params(other: Index).void }
    def merge!(other)
      @entries.merge!(other.entries)
      @entries_tree.merge!(other.entries_tree)
      @files_to_entries.merge!(other.files_to_entries)
      @require_paths_tree.merge!(other.require_paths_tree)
    end

    class Entry
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :file_path

      sig { returns(YARP::Location) }
      attr_reader :location

      sig { returns(T::Array[String]) }
      attr_reader :comments

      sig { returns(Symbol) }
      attr_accessor :visibility

      sig { params(name: String, file_path: String, location: YARP::Location, comments: T::Array[String]).void }
      def initialize(name, file_path, location, comments)
        @name = name
        @file_path = file_path
        @location = location
        @comments = comments
        @visibility = T.let(:public, Symbol)
      end

      sig { returns(String) }
      def file_name
        File.basename(@file_path)
      end

      class Namespace < Entry
        sig { returns(String) }
        def short_name
          T.must(@name.split("::").last)
        end
      end

      class Module < Namespace
      end

      class Class < Namespace
      end

      class Constant < Entry
      end
    end
  end
end
