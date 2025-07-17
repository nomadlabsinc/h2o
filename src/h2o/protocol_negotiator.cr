require "./types"

module H2O
  # Protocol negotiator following SRP principles
  # Determines HTTP/2 vs HTTP/1.1 support and manages protocol caching
  class ProtocolNegotiator
    # Protocol support cache entry
    private struct ProtocolCacheEntry
      property protocol : String
      property cached_at : Time
      property confidence : Float64

      def initialize(@protocol : String, @confidence : Float64 = 1.0)
        @cached_at = Time.utc
      end

      def expired?(ttl : Time::Span = 1.hour) : Bool
        Time.utc - @cached_at > ttl
      end
    end

    @protocol_cache : Hash(String, ProtocolCacheEntry)
    @h2_prior_knowledge : Bool
    @cache_ttl : Time::Span
    @mutex : Mutex

    def initialize(@h2_prior_knowledge : Bool = false, @cache_ttl : Time::Span = 1.hour)
      @protocol_cache = Hash(String, ProtocolCacheEntry).new
      @mutex = Mutex.new
    end

    # Determine the best protocol for a given host and port
    def negotiate_protocol(host : String, port : Int32) : String
      cache_key = "#{host}:#{port}"

      # Check cache first
      if cached_entry = get_cached_protocol(cache_key)
        return cached_entry.protocol
      end

      # Perform negotiation
      protocol = perform_negotiation(host, port)

      # Cache the result
      cache_protocol(cache_key, protocol)

      protocol
    end

    # Create appropriate connection based on negotiated protocol
    def create_connection(host : String, port : Int32, use_tls : Bool, verify_ssl : Bool) : BaseConnection
      protocol = negotiate_protocol(host, port)

      case protocol
      when "h2"
        H2::Client.new(host, port, verify_ssl: verify_ssl, use_tls: use_tls)
      when "http/1.1"
        H1::Client.new(host, port, verify_ssl: verify_ssl)
      else
        # Default to HTTP/2 if uncertain
        H2::Client.new(host, port, verify_ssl: verify_ssl, use_tls: use_tls)
      end
    end

    # Check if host supports HTTP/2
    def supports_http2?(host : String, port : Int32) : Bool
      protocol = negotiate_protocol(host, port)
      protocol == "h2"
    end

    # Force protocol for specific host (useful for testing)
    def force_protocol(host : String, port : Int32, protocol : String, confidence : Float64 = 1.0) : Nil
      cache_key = "#{host}:#{port}"
      cache_protocol(cache_key, protocol, confidence)
    end

    # Clear protocol cache
    def clear_cache : Nil
      @mutex.synchronize do
        @protocol_cache.clear
      end
    end

    # Remove expired cache entries
    def cleanup_expired_cache : Nil
      @mutex.synchronize do
        expired_keys = [] of String

        @protocol_cache.each do |key, entry|
          if entry.expired?(@cache_ttl)
            expired_keys << key
          end
        end

        expired_keys.each { |key| @protocol_cache.delete(key) }
      end
    end

    # Get negotiation statistics
    def statistics : Hash(Symbol, Int32 | Float64)
      @mutex.synchronize do
        total_entries = @protocol_cache.size
        h2_entries = @protocol_cache.values.count(&.protocol.== "h2")
        h1_entries = @protocol_cache.values.count(&.protocol.== "http/1.1")
        avg_confidence = @protocol_cache.values.sum(&.confidence) / Math.max(total_entries, 1)

        {
          :total_cached_hosts => total_entries,
          :h2_hosts           => h2_entries,
          :h1_hosts           => h1_entries,
          :h2_ratio           => total_entries > 0 ? h2_entries.to_f64 / total_entries.to_f64 : 0.0,
          :avg_confidence     => avg_confidence,
          :cache_ttl_hours    => @cache_ttl.total_hours,
        }
      end
    end

    # Get all cached protocols
    def cached_protocols : Hash(String, String)
      @mutex.synchronize do
        result = Hash(String, String).new
        @protocol_cache.each do |key, entry|
          result[key] = entry.protocol
        end
        result
      end
    end

    # Check if protocol is cached for host
    def protocol_cached?(host : String, port : Int32) : Bool
      @mutex.synchronize do
        cache_key = "#{host}:#{port}"
        entry = @protocol_cache[cache_key]?
        !!(entry && !entry.expired?(@cache_ttl))
      end
    end

    private def get_cached_protocol(cache_key : String) : ProtocolCacheEntry?
      @mutex.synchronize do
        entry = @protocol_cache[cache_key]?
        return nil unless entry

        if entry.expired?(@cache_ttl)
          @protocol_cache.delete(cache_key)
          return nil
        end

        entry
      end
    end

    private def perform_negotiation(host : String, port : Int32) : String
      # If h2_prior_knowledge is enabled, always use HTTP/2
      return "h2" if @h2_prior_knowledge

      # Determine if TLS is likely based on port
      use_tls = tls_port?(port)

      # Try HTTP/2 negotiation first
      if use_tls
        negotiate_via_alpn(host, port)
      else
        # For cleartext, try HTTP/2 upgrade
        negotiate_via_upgrade(host, port)
      end
    end

    private def negotiate_via_alpn(host : String, port : Int32) : String
      # Try HTTP/2 first via ALPN
      context = OpenSSL::SSL::Context::Client.new
      context.alpn_protocol = "h2"

      socket = TCPSocket.new(host, port)
      ssl_socket = OpenSSL::SSL::Socket::Client.new(socket, context: context, hostname: host)

      # Check negotiated protocol
      negotiated_protocol = ssl_socket.alpn_protocol
      ssl_socket.close

      case negotiated_protocol
      when "h2"
        "h2"
      when "http/1.1", nil
        # Server doesn't support HTTP/2, fall back to HTTP/1.1
        "http/1.1"
      else
        "http/1.1"
      end
    rescue ex : OpenSSL::SSL::Error
      # SSL errors often indicate no HTTP/2 support
      if ex.message.try(&.includes?("no protocols available")) ||
         ex.message.try(&.includes?("wrong version number"))
        "http/1.1"
      else
        # For other SSL errors, default to HTTP/1.1
        "http/1.1"
      end
    rescue ex : IO::TimeoutError | Socket::ConnectError
      # Connection errors - default to HTTP/1.1
      "http/1.1"
    rescue ex
      # Other errors - log and default to HTTP/1.1
      Log.warn { "Protocol negotiation failed for #{host}:#{port}: #{ex.message}" }
      "http/1.1"
    end

    private def negotiate_via_upgrade(host : String, port : Int32) : String
      # For cleartext connections, HTTP/2 requires upgrade
      # This is complex and rarely used, so default to HTTP/1.1
      # In production, most HTTP/2 is over TLS
      "http/1.1"
    end

    private def tls_port?(port : Int32) : Bool
      # Common HTTPS ports
      [443, 8443, 8445, 8447].includes?(port)
    end

    private def cache_protocol(cache_key : String, protocol : String, confidence : Float64 = 1.0) : Nil
      @mutex.synchronize do
        @protocol_cache[cache_key] = ProtocolCacheEntry.new(protocol, confidence)
      end
    end
  end
end
