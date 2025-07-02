module H2O
  # String interning pool for common HTTP headers
  class StringPool
    # Common HTTP/2 headers that benefit from interning
    COMMON_HEADERS = {
      # HTTP/2 pseudo-headers
      ":authority", ":method", ":path", ":scheme", ":status",

      # Common request headers
      "accept", "accept-charset", "accept-encoding", "accept-language",
      "access-control-request-headers", "access-control-request-method",
      "authorization", "cache-control", "connection", "content-encoding",
      "content-language", "content-length", "content-location", "content-type",
      "cookie", "date", "etag", "expect", "expires", "from", "host",
      "if-match", "if-modified-since", "if-none-match", "if-range",
      "if-unmodified-since", "last-modified", "location", "max-forwards",
      "origin", "pragma", "proxy-authenticate", "proxy-authorization",
      "range", "referer", "retry-after", "server", "set-cookie",
      "strict-transport-security", "te", "trailer", "transfer-encoding",
      "upgrade", "user-agent", "vary", "via", "warning", "www-authenticate",

      # Common response headers
      "accept-ranges", "age", "allow", "content-disposition", "content-range",
      "link", "refresh", "x-content-type-options", "x-frame-options",
      "x-powered-by", "x-requested-with", "x-ua-compatible", "x-xss-protection",

      # Common values
      "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH",
      "200", "201", "204", "301", "302", "304", "400", "401", "403", "404", "500",
      "application/json", "application/xml", "text/html", "text/plain",
      "text/css", "text/javascript", "image/png", "image/jpeg", "image/gif",
      "gzip", "deflate", "br", "identity", "close", "keep-alive",
      "no-cache", "no-store", "max-age=0", "must-revalidate",
    }

    property pool : Hash(String, String)
    property mutex : Mutex
    property stats : PoolStats

    struct PoolStats
      property hits : Int64 = 0_i64
      property misses : Int64 = 0_i64
      property bytes_saved : Int64 = 0_i64

      def hit_rate : Float64
        total = hits + misses
        total > 0 ? hits.to_f64 / total : 0.0
      end
    end

    def initialize
      @pool = Hash(String, String).new
      @mutex = Mutex.new
      @stats = PoolStats.new

      # Pre-populate with common headers
      COMMON_HEADERS.each do |header|
        @pool[header] = header
      end
    end

    # Intern a string - returns the pooled version if available
    def intern(str : String) : String
      @mutex.synchronize do
        if pooled = @pool[str]?
          @stats.hits += 1
          @stats.bytes_saved += str.bytesize
          pooled
        else
          @stats.misses += 1
          # Only pool strings that are likely to be reused
          if should_pool?(str)
            @pool[str] = str
          end
          str
        end
      end
    end

    # Check if multiple strings can be interned
    def intern_all(strings : Array(String)) : Array(String)
      strings.map { |str| intern(str) }
    end

    # Intern header name/value pairs
    def intern_headers(headers : Headers) : Headers
      interned = Headers.new
      headers.each do |name, value|
        interned[intern(name)] = intern(value)
      end
      interned
    end

    private def should_pool?(str : String) : Bool
      # Pool strings that are:
      # 1. Not too long (to avoid memory bloat)
      # 2. Look like headers or common values
      # 3. Not dynamic values (like timestamps)

      return false if str.size > 256
      return false if str.matches?(/\d{4}-\d{2}-\d{2}/)  # Dates
      return false if str.matches?(/\d+\.\d+\.\d+\.\d+/) # IPs

      # Pool if it looks like a header name (lowercase with dashes)
      return true if str.matches?(/^[a-z][a-z\-]*$/)

      # Pool if it's a common MIME type
      return true if str.includes?("/") && str.matches?(/^[a-z]+\/[a-z\-\+]+$/)

      # Pool if it's a short value that might be repeated
      str.size < 50
    end

    def size : Int32
      @mutex.synchronize { @pool.size }
    end

    def clear : Nil
      @mutex.synchronize do
        @pool.clear
        @stats = PoolStats.new

        # Re-populate with common headers
        COMMON_HEADERS.each do |header|
          @pool[header] = header
        end
      end
    end

    def statistics : PoolStats
      @mutex.synchronize { @stats }
    end
  end

  # REMOVED: Global string pool to prevent malloc corruption
  # Each client should have its own string pool instance if needed
  # @@string_pool : StringPool? = nil
  #
  # def self.string_pool : StringPool
  #   @@string_pool ||= StringPool.new
  # end
  #
  # def self.string_pool=(pool : StringPool) : StringPool
  #   @@string_pool = pool
  # end
end
