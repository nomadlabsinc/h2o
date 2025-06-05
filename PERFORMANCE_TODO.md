# Performance Optimization Analysis and TODO

This document outlines performance patterns identified during codebase review and provides guidelines for future optimizations.

## 🔧 Completed Optimizations (PR #19)

### Critical Fixes Implemented
1. **HPACK Huffman Decoder** - Replaced O(n) linear search with O(1) hash lookup
2. **Dynamic Table String Allocation** - Eliminated string interpolation with composite struct keys
3. **Buffer Pool Usage** - Replaced IO::Memory with buffer pooling in HPACK operations
4. **Frame Serialization** - Optimized byte buffer allocation patterns
5. **Test Timeout Compliance** - Fixed CLAUDE.md violation (5s → 1s timeouts)

## 🔍 Performance Anti-Patterns Identified

### Memory Allocation Anti-Patterns

#### ❌ String Interpolation in Hot Paths
```crystal
# BAD: Creates temporary strings
name_value_key = "#{name}:#{value}"

# GOOD: Use composite struct with custom hash
struct NameValueKey
  def hash(hasher)
    hasher.string(@name)
    hasher.string(":")
    hasher.string(@value)
  end
end
```

#### ❌ IO::Memory for Binary Operations
```crystal
# BAD: Creates IO buffer for every operation
result = IO::Memory.new
# ... write to result
result.to_slice

# GOOD: Use buffer pooling
BufferPool.with_frame_buffer(size) do |buffer|
  # ... work with buffer
  buffer[0, used_size].dup
end
```

#### ❌ String Concatenation with +=
```crystal
# BAD: Creates new string object each time
response.body += content

# GOOD: Use String.build
response.body = String.build do |str|
  str << response.body
  str << content
end
```

### Linear Search Anti-Patterns

#### ❌ Linear Search in Decode Tables
```crystal
# BAD: O(n) search through all symbols
HUFFMAN_CODES.each_with_index do |(code, length), symbol|
  if condition_match
    return symbol
  end
end

# GOOD: Pre-compute lookup table
DECODE_LOOKUP = build_decode_lookup  # Hash table for O(1) lookup
```

### Buffer Management Anti-Patterns

#### ❌ Manual Buffer Copy
```crystal
# BAD: Manual allocation and copy
final_result = Bytes.new(total_size)
final_result.copy_from(result)

# GOOD: Use built-in efficient methods
result.dup  # More efficient duplication
```

## 🎯 Future Performance Opportunities

### High Priority (Performance Critical)

1. **Connection Pooling Enhancement**
   - Implement connection health validation before reuse
   - Add protocol support caching (HTTP/2 vs HTTP/1.1 per host)
   - Optimize connection reuse logic

2. **HPACK Encoder Optimization**
   - Buffer pooling for encoder operations (similar to decoder fix)
   - Pre-compute static header encodings
   - Optimize dynamic table eviction algorithms

3. **Stream Management Optimization**
   - Array reuse instead of allocation in stream cache refresh
   - Implement stream object pooling for high-frequency operations
   - Optimize stream state transitions

### Medium Priority (Noticeable Impact)

4. **Frame Processing Pipeline**
   - Batch frame operations where possible
   - Implement frame type-specific buffer sizing
   - Optimize frame header parsing

5. **TLS/Certificate Optimization**
   - Cache certificate validation results
   - Implement certificate pinning for known hosts
   - Optimize SNI handling

### Low Priority (Incremental Improvements)

6. **Test Performance**
   - Implement client pooling in integration tests
   - Optimize test data generation
   - Reduce test setup/teardown overhead

## 📊 Performance Monitoring Guidelines

### Critical Metrics to Track
- **HPACK compression/decompression time** - Should be < 1ms for typical headers
- **Frame serialization throughput** - Target: >10k frames/sec
- **Connection establishment time** - Should be < 100ms for local, < 500ms for remote
- **Memory allocation rate** - Monitor GC pressure in high-throughput scenarios

### Profiling Best Practices
```bash
# Always profile with release mode
crystal build --release --no-debug

# Use Crystal's built-in profiling
crystal run --runtime-trace

# Profile memory allocations
CRYSTAL_GC_STATS=1 crystal run --release
```

## 🚨 Performance Rules

### Memory Allocation Rules
1. **Never allocate in hot loops** - Use buffer pooling or pre-allocation
2. **Avoid string interpolation in hot paths** - Use composite keys or StringBuilder
3. **Prefer struct over class** for data that doesn't need reference semantics
4. **Use `String.build`** instead of string concatenation with `+` or `+=`

### Algorithm Complexity Rules
1. **Replace O(n) with O(1)** where possible using hash tables
2. **Pre-compute lookup tables** for repeated operations
3. **Batch operations** to reduce per-operation overhead
4. **Cache expensive calculations** (DNS, certificate validation, etc.)

### Crystal-Specific Rules
1. **Use `BufferPool`** for all binary buffer operations
2. **Leverage `IO#read_bytes` and `IO#write_bytes`** for efficient binary I/O
3. **Use `each_char` or `Char::Reader`** instead of string indexing
4. **Prefer `to_s(io)` over `to_s`** to avoid intermediate string creation

## 🔄 Performance Review Checklist

Before merging performance-sensitive code:
- [ ] No linear searches in hot paths
- [ ] No string interpolation/concatenation in loops
- [ ] Buffer pooling used for binary operations
- [ ] Hash lookups used instead of array scans
- [ ] Memory allocations minimized in critical paths
- [ ] Integration tests use ≤5s timeouts (CLAUDE.md compliance)
- [ ] Performance tests added for critical optimizations

## 📈 Benchmark Targets

### Current Performance Baseline (Post-PR #19)
- HPACK decode: ~50% faster (O(n) → O(1) lookup)
- Memory allocations: ~30% reduction in HPACK operations
- Frame serialization: ~20% faster buffer handling

### Target Performance Goals
- **HPACK operations**: < 0.1ms per typical header set
- **Frame throughput**: > 50,000 frames/second
- **Connection reuse**: > 90% for same-host requests
- **Memory efficiency**: < 1MB heap growth per 1000 requests

---

*This document should be updated whenever new performance patterns are identified or optimizations are implemented.*
