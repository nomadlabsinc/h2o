# HPACK Layer Implementation

This directory contains the Layer 3 implementation of the H2O HTTP/2 client refactor:
**HPACK (Header Compression)** as defined in RFC 7541.

## Architecture Overview

The HPACK implementation strictly follows the Single Responsibility Principle (SRP) 
and is designed as a stateful compression layer isolated from connection management.

### Core Components

- **`encoder.cr`**: HPACK encoder with both full and fast encoding modes
- **`decoder.cr`**: HPACK decoder with comprehensive security validation
- **`dynamic_table.cr`**: Dynamic table management with O(1) lookups
- **`static_table.cr`**: Static table implementation following RFC 7541
- **`huffman.cr`**: Huffman encoding/decoding with lookup tables
- **`strict_validation.cr`**: Security validation module
- **`presets.cr`**: HPACK presets for different use cases

### Key Design Principles

1. **Per-Connection State**: Each `H2O::H2::Client` instance maintains its own 
   `HPACK::Encoder` and `HPACK::Decoder` to manage dynamic table state correctly.

2. **Security by Default**: All components integrate `HpackSecurityLimits` and 
   `StrictValidation` to prevent HPACK bomb attacks and resource exhaustion.

3. **Performance Optimized**: Includes both full HPACK encoding and fast 
   static-table-only encoding for different performance requirements.

4. **Memory Safe**: Avoids object pooling to prevent memory corruption issues,
   relying on Crystal's garbage collector for memory management.

## Integration Pattern

```crystal
# In H2O::H2::Client
@hpack_encoder = HPACK::Encoder.new
@hpack_decoder = HPACK::Decoder.new(4096, HpackSecurityLimits.new)
```

This ensures:
- **Isolated state**: Each connection has its own compression context
- **Security limits**: Explicit security configuration prevents attacks
- **Clean separation**: HPACK layer is decoupled from connection management

## SRP Compliance

This layer strictly handles header compression concerns and is isolated from:
- **Layer 1**: Transport (TCP/TLS socket management)
- **Layer 2**: Framing (HTTP/2 frame protocol)
- **Layer 4**: Connection Management (HTTP/2 connection state)
- **Layer 5**: Stream Management (HTTP/2 stream multiplexing)

The HPACK layer provides a clean API for header compression/decompression that 
higher layers can use without understanding the implementation details.