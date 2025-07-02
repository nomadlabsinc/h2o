# Malloc Corruption Root Cause Analysis and Fix

## Root Cause

The malloc corruption occurs due to **global shared state** that is accessed concurrently by multiple H2O client instances without proper synchronization at the global level. 

### Critical Issues Found:

1. **Global TLS Cache** (`@@tls_cache`)
   - Shared across all client instances
   - Uses LRU eviction with linked list manipulation
   - Can cause memory corruption when multiple clients trigger eviction simultaneously

2. **Global String Pool** (`@@string_pool`)
   - Shared hash table for string interning
   - Concurrent modifications can corrupt the hash table structure

3. **Global Buffer Pool Stats** (`@@buffer_pool_stats`)
   - Uses atomic operations but still represents shared state

## The Fix

### Option 1: Make Caches Instance-Based (Recommended)
Remove all global state and make caches instance-based per client:

```crystal
# In src/h2o/client.cr
class Client
  property tls_cache : TLSCache
  property string_pool : StringPool
  
  def initialize(...)
    @tls_cache = TLSCache.new
    @string_pool = StringPool.new
    # ... other initialization
  end
end
```

### Option 2: Add Global Synchronization
Wrap all global cache access in a global mutex:

```crystal
module H2O
  @@global_mutex = Mutex.new
  
  def self.tls_cache : TLSCache
    @@global_mutex.synchronize do
      @@tls_cache ||= TLSCache.new
    end
  end
end
```

### Option 3: Disable Caching (Quick Fix)
Temporarily disable all caching to verify this is the issue:

```crystal
# In src/h2o/tls.cr
# Comment out all cache access
# H2O.tls_cache.get_sni(hostname) || hostname
sni_name = hostname  # Direct assignment, no cache
```

## Implementation Plan

1. First, verify the fix by disabling the global TLS cache
2. Run stress tests to confirm malloc corruption is gone
3. Implement proper instance-based caching
4. Add thread-safety tests

## Test Case to Reproduce

```crystal
# This should trigger the malloc corruption
100.times do |i|
  spawn do
    client = H2O::Client.new
    response = client.get("https://httpbin.org/get")
    client.close
  end
end

sleep 5
```

## Memory Safety Guidelines

1. **Never use global mutable state** in concurrent environments
2. **Always use instance-based state** for client-specific data
3. **If global state is needed**, protect it with proper synchronization
4. **Test with multiple concurrent clients** to catch these issues early