module H2O
  # Simple LRU Cache implementation
  class LRUCache(K, V)
    class Node(K, V)
      property key : K
      property value : V
      property prev : Node(K, V)?
      property next : Node(K, V)?

      def initialize(@key : K, @value : V, @prev = nil, @next = nil)
      end
    end

    property capacity : Int32
    property cache : Hash(K, Node(K, V))
    property head : Node(K, V)?
    property tail : Node(K, V)?

    def initialize(@capacity : Int32)
      @cache = Hash(K, Node(K, V)).new
      @head = nil
      @tail = nil
    end

    def get(key : K) : V?
      return nil unless node = @cache[key]?

      # Move to front
      remove_node(node)
      add_to_front(node)

      node.value
    end

    def set(key : K, value : V) : Nil
      if node = @cache[key]?
        # Update existing
        node.value = value
        remove_node(node)
        add_to_front(node)
      else
        # Add new
        node = Node(K, V).new(key, value)
        @cache[key] = node
        add_to_front(node)

        # Evict if over capacity
        if @cache.size > @capacity
          evict_lru
        end
      end
    end

    def delete(key : K) : V?
      return nil unless node = @cache.delete(key)
      remove_node(node)
      node.value
    end

    def clear : Nil
      @cache.clear
      @head = nil
      @tail = nil
    end

    def size : Int32
      @cache.size
    end

    private def add_to_front(node : Node(K, V)) : Nil
      node.prev = nil
      node.next = @head

      if h = @head
        h.prev = node
      end

      @head = node
      @tail = node if @tail.nil?
    end

    private def remove_node(node : Node(K, V)) : Nil
      if prev_node = node.prev
        prev_node.next = node.next
      else
        @head = node.next
      end

      if next_node = node.next
        next_node.prev = node.prev
      else
        @tail = node.prev
      end
    end

    private def evict_lru : Nil
      return unless t = @tail

      @cache.delete(t.key)
      remove_node(t)
    end
  end

  # Certificate validation result for caching
  struct CertValidationResult
    property valid : Bool
    property subject : String
    property issuer : String
    property expires : Time
    property validated_at : Time

    def initialize(@valid : Bool, @subject : String, @issuer : String, @expires : Time)
      @validated_at = Time.utc
    end

    def expired? : Bool
      Time.utc > @expires
    end

    def cache_stale?(max_age : Time::Span = 1.hour) : Bool
      Time.utc - @validated_at > max_age
    end
  end

  # TLS session cache entry
  struct TLSSessionEntry
    property session_id : Bytes
    property session_ticket : Bytes?
    property created_at : Time
    property last_used : Time
    property reuse_count : Int32

    def initialize(@session_id : Bytes, @session_ticket : Bytes? = nil)
      @created_at = Time.utc
      @last_used = Time.utc
      @reuse_count = 0
    end

    def mark_used : Nil
      @last_used = Time.utc
      @reuse_count += 1
    end

    def age : Time::Span
      Time.utc - @created_at
    end

    def idle_time : Time::Span
      Time.utc - @last_used
    end

    def stale?(max_age : Time::Span = 24.hours, max_idle : Time::Span = 1.hour) : Bool
      age > max_age || idle_time > max_idle
    end
  end

  # SNI cache entry
  struct SNIEntry
    property hostname : String
    property resolved_name : String
    property created_at : Time

    def initialize(@hostname : String, @resolved_name : String)
      @created_at = Time.utc
    end

    def age : Time::Span
      Time.utc - @created_at
    end

    def stale?(max_age : Time::Span = 1.hour) : Bool
      age > max_age
    end
  end

  # TLS optimization cache manager
  class TLSCache
    # Cache sizes
    CERT_CACHE_SIZE    =  1000
    SESSION_CACHE_SIZE = 10000
    SNI_CACHE_SIZE     =  1000

    # Type aliases for caches
    alias CertCache = LRUCache(String, CertValidationResult)
    alias SessionCache = LRUCache(String, TLSSessionEntry)
    alias SNICache = LRUCache(String, SNIEntry)

    property cert_cache : CertCache
    property session_cache : SessionCache
    property sni_cache : SNICache
    property stats : CacheStats

    struct CacheStats
      property cert_hits : Int64 = 0_i64
      property cert_misses : Int64 = 0_i64
      property session_hits : Int64 = 0_i64
      property session_misses : Int64 = 0_i64
      property sni_hits : Int64 = 0_i64
      property sni_misses : Int64 = 0_i64

      def cert_hit_rate : Float64
        total = cert_hits + cert_misses
        total > 0 ? cert_hits.to_f64 / total : 0.0
      end

      def session_hit_rate : Float64
        total = session_hits + session_misses
        total > 0 ? session_hits.to_f64 / total : 0.0
      end

      def sni_hit_rate : Float64
        total = sni_hits + sni_misses
        total > 0 ? sni_hits.to_f64 / total : 0.0
      end
    end

    def initialize(cert_size : Int32 = CERT_CACHE_SIZE,
                   session_size : Int32 = SESSION_CACHE_SIZE,
                   sni_size : Int32 = SNI_CACHE_SIZE)
      @cert_cache = CertCache.new(cert_size)
      @session_cache = SessionCache.new(session_size)
      @sni_cache = SNICache.new(sni_size)
      @stats = CacheStats.new
      @mutex = Mutex.new
    end

    # Certificate validation caching
    def get_cert_validation(cert_fingerprint : String) : CertValidationResult?
      @mutex.synchronize do
        if result = @cert_cache.get(cert_fingerprint)
          unless result.cache_stale? || result.expired?
            @stats.cert_hits += 1
            return result
          end
          # Remove stale entry
          @cert_cache.delete(cert_fingerprint)
        end
        @stats.cert_misses += 1
        nil
      end
    end

    def set_cert_validation(cert_fingerprint : String, result : CertValidationResult) : Nil
      @mutex.synchronize do
        @cert_cache.set(cert_fingerprint, result)
      end
    end

    # TLS session caching for session resumption
    def get_session(host_port : String) : TLSSessionEntry?
      @mutex.synchronize do
        if entry = @session_cache.get(host_port)
          unless entry.stale?
            entry.mark_used
            @stats.session_hits += 1
            return entry
          end
          # Remove stale entry
          @session_cache.delete(host_port)
        end
        @stats.session_misses += 1
        nil
      end
    end

    def set_session(host_port : String, session_id : Bytes, session_ticket : Bytes? = nil) : Nil
      @mutex.synchronize do
        entry = TLSSessionEntry.new(session_id, session_ticket)
        @session_cache.set(host_port, entry)
      end
    end

    # SNI caching
    def get_sni(hostname : String) : String?
      @mutex.synchronize do
        if entry = @sni_cache.get(hostname)
          unless entry.stale?
            @stats.sni_hits += 1
            return entry.resolved_name
          end
          # Remove stale entry
          @sni_cache.delete(hostname)
        end
        @stats.sni_misses += 1
        nil
      end
    end

    def set_sni(hostname : String, resolved_name : String) : Nil
      @mutex.synchronize do
        entry = SNIEntry.new(hostname, resolved_name)
        @sni_cache.set(hostname, entry)
      end
    end

    # Clear all caches
    def clear : Nil
      @mutex.synchronize do
        @cert_cache.clear
        @session_cache.clear
        @sni_cache.clear
      end
    end

    # Get cache statistics
    def statistics : CacheStats
      @mutex.synchronize { @stats }
    end
  end

  # REMOVED: Global TLS cache to prevent malloc corruption
  # Each client should have its own TLS cache instance
  # @@tls_cache : TLSCache? = nil
  #
  # def self.tls_cache : TLSCache
  #   @@tls_cache ||= TLSCache.new
  # end
  #
  # def self.tls_cache=(cache : TLSCache) : TLSCache
  #   @@tls_cache = cache
  # end
end
