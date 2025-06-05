module H2O::HPACK
  class DynamicTable
    DEFAULT_SIZE = 4096

    property max_size : Int32
    property current_size : Int32
    property entries : Array(StaticEntry)

    def initialize(@max_size : Int32 = DEFAULT_SIZE)
      @current_size = 0
      @entries = Array(StaticEntry).new
      @name_index = Hash(String, Int32).new
      @name_value_index = Hash(String, Int32).new
    end

    def resize(new_size : Int32) : Nil
      @max_size = new_size
      evict_entries
    end

    def add(name : String, value : String) : Nil
      entry = StaticEntry.new(name, value)
      @entries.unshift(entry)
      @current_size += entry.size

      index = StaticTable.size + 1
      @name_index[name] = index unless @name_index.has_key?(name)
      name_value_key = "#{name}:#{value}"
      @name_value_index[name_value_key] = index

      evict_entries
    end

    def [](index : Int32) : StaticEntry?
      static_size = StaticTable.size

      if index <= static_size
        StaticTable[index]
      else
        dynamic_index = index - static_size - 1
        return nil if dynamic_index < 0 || dynamic_index >= @entries.size
        @entries[dynamic_index]
      end
    end

    def find_name(name : String) : Int32?
      static_index = StaticTable.find_name(name)
      return static_index if static_index

      @name_index[name]?
    end

    def find_name_value(name : String, value : String) : Int32?
      static_index = StaticTable.find_name_value(name, value)
      return static_index if static_index

      name_value_key = "#{name}:#{value}"
      @name_value_index[name_value_key]?
    end

    def size : Int32
      StaticTable.size + @entries.size
    end

    def dynamic_size : Int32
      @entries.size
    end

    private def evict_entries : Nil
      while @current_size > @max_size && !@entries.empty?
        entry = @entries.pop
        @current_size -= entry.size
        rebuild_indices
      end
    end

    private def rebuild_indices : Nil
      @name_index.clear
      @name_value_index.clear

      @entries.each_with_index do |entry, index|
        table_index = StaticTable.size + index + 1
        @name_index[entry.name] = table_index unless @name_index.has_key?(entry.name)
        name_value_key = "#{entry.name}:#{entry.value}"
        @name_value_index[name_value_key] = table_index
      end
    end
  end
end
