module H2O::HPACK
  # Simplified static entry without expensive pre-computation
  struct StaticEntry
    property name : String
    property value : String

    def initialize(@name : String, @value : String = "")
    end

    def size : Int32
      @name.bytesize + @value.bytesize + 32
    end
  end

  module StaticTable
    # Simplified static entries for O(1) lookups
    STATIC_ENTRIES = [
      StaticEntry.new(":authority", ""),
      StaticEntry.new(":method", "GET"),
      StaticEntry.new(":method", "POST"),
      StaticEntry.new(":path", "/"),
      StaticEntry.new(":path", "/index.html"),
      StaticEntry.new(":scheme", "http"),
      StaticEntry.new(":scheme", "https"),
      StaticEntry.new(":status", "200"),
      StaticEntry.new(":status", "204"),
      StaticEntry.new(":status", "206"),
      StaticEntry.new(":status", "304"),
      StaticEntry.new(":status", "400"),
      StaticEntry.new(":status", "404"),
      StaticEntry.new(":status", "500"),
      StaticEntry.new("accept-charset", ""),
      StaticEntry.new("accept-encoding", "gzip, deflate"),
      StaticEntry.new("accept-language", ""),
      StaticEntry.new("accept-ranges", ""),
      StaticEntry.new("accept", ""),
      StaticEntry.new("access-control-allow-origin", ""),
      StaticEntry.new("age", ""),
      StaticEntry.new("allow", ""),
      StaticEntry.new("authorization", ""),
      StaticEntry.new("cache-control", ""),
      StaticEntry.new("content-disposition", ""),
      StaticEntry.new("content-encoding", ""),
      StaticEntry.new("content-language", ""),
      StaticEntry.new("content-length", ""),
      StaticEntry.new("content-location", ""),
      StaticEntry.new("content-range", ""),
      StaticEntry.new("content-type", ""),
      StaticEntry.new("cookie", ""),
      StaticEntry.new("date", ""),
      StaticEntry.new("etag", ""),
      StaticEntry.new("expect", ""),
      StaticEntry.new("expires", ""),
      StaticEntry.new("from", ""),
      StaticEntry.new("host", ""),
      StaticEntry.new("if-match", ""),
      StaticEntry.new("if-modified-since", ""),
      StaticEntry.new("if-none-match", ""),
      StaticEntry.new("if-range", ""),
      StaticEntry.new("if-unmodified-since", ""),
      StaticEntry.new("last-modified", ""),
      StaticEntry.new("link", ""),
      StaticEntry.new("location", ""),
      StaticEntry.new("max-forwards", ""),
      StaticEntry.new("proxy-authenticate", ""),
      StaticEntry.new("proxy-authorization", ""),
      StaticEntry.new("range", ""),
      StaticEntry.new("referer", ""),
      StaticEntry.new("refresh", ""),
      StaticEntry.new("retry-after", ""),
      StaticEntry.new("server", ""),
      StaticEntry.new("set-cookie", ""),
      StaticEntry.new("strict-transport-security", ""),
      StaticEntry.new("transfer-encoding", ""),
      StaticEntry.new("user-agent", ""),
      StaticEntry.new("vary", ""),
      StaticEntry.new("via", ""),
      StaticEntry.new("www-authenticate", ""),
    ]

    # Enhanced O(1) lookup indices with header name normalization caching
    NAME_INDEX = STATIC_ENTRIES.each_with_index.reduce(Hash(String, Int32).new) do |hash, (entry, index)|
      hash[entry.name] = index + 1 unless hash.has_key?(entry.name)
      hash
    end

    NAME_VALUE_INDEX = STATIC_ENTRIES.each_with_index.reduce(Hash(String, Int32).new) do |hash, (entry, index)|
      key = String.build do |k|
        k << entry.name << ':' << entry.value
      end
      hash[key] = index + 1
      hash
    end

    # Fast header name normalization without expensive caching
    def self.normalize_header_name(name : String) : String
      # Skip normalization if already lowercase (common case)
      return name if name == name.downcase
      name.downcase
    end

    def self.size : Int32
      STATIC_ENTRIES.size
    end

    def self.[](index : Int32) : StaticEntry?
      return nil if index < 1 || index > STATIC_ENTRIES.size
      STATIC_ENTRIES[index - 1]
    end

    def self.find_name(name : String) : Int32?
      normalized_name = normalize_header_name(name)
      NAME_INDEX[normalized_name]?
    end

    def self.find_name_value(name : String, value : String) : Int32?
      normalized_name = normalize_header_name(name)
      name_value_key = "#{normalized_name}:#{value}"
      NAME_VALUE_INDEX[name_value_key]?
    end
  end
end
