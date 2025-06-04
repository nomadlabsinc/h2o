module H2O::HPACK
  class DynamicTable
    DEFAULT_SIZE = 4096

    property max_size : Int32
    property current_size : Int32
    property entries : Array(StaticEntry)

    def initialize(@max_size : Int32 = DEFAULT_SIZE)
      @current_size = 0
      @entries = Array(StaticEntry).new
    end

    def resize(new_size : Int32) : Nil
      @max_size = new_size
      evict_entries
    end

    def add(name : String, value : String) : Nil
      entry = StaticEntry.new(name, value)
      @entries.unshift(entry)
      @current_size += entry.size
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

      @entries.each_with_index do |entry, index|
        return StaticTable.size + index + 1 if entry.name == name
      end

      nil
    end

    def find_name_value(name : String, value : String) : Int32?
      static_index = StaticTable.find_name_value(name, value)
      return static_index if static_index

      @entries.each_with_index do |entry, index|
        return StaticTable.size + index + 1 if entry.name == name && entry.value == value
      end

      nil
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
      end
    end
  end
end
