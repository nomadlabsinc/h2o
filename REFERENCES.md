# HTTP/2 Implementation References

This document lists high-quality HTTP/2 implementations across different programming languages that serve as excellent references for spec compliance, testing patterns, and API design.

## Go

### net/http (standard library)
- Most spec-compliant, maintained by Go team
- Built-in HTTP/2 support with automatic protocol negotiation
- Comprehensive test suite, excellent type safety
- Reference implementation quality

### golang.org/x/net/http2
- Lower-level HTTP/2 implementation
- Used internally by net/http
- Good for understanding protocol details

## Rust

### hyper crate
- Industry standard, highly spec-compliant
- Excellent type system usage with Rust's ownership model
- Comprehensive async support and testing
- Powers many production systems

### reqwest crate
- High-level client built on hyper
- Excellent ergonomics and type safety
- Good reference for API design

### h2 crate
- Pure HTTP/2 implementation
- Low-level, spec-focused
- Excellent for protocol implementation details

## C#/.NET

### System.Net.Http.HttpClient
- Microsoft's official implementation
- Strong typing with generics
- Excellent async/await patterns
- Good multiplexing support

## TypeScript/Node.js

### node:http2 (built-in)
- Node.js standard library
- Good TypeScript definitions
- Spec-compliant implementation

## Recommendations for Crystal Development

For Crystal shard reference, I'd recommend studying Go's net/http and Rust's hyper as they have the best combination of spec compliance, comprehensive testing, and clean typed APIs that would translate well to Crystal's type system.

### Key Learning Areas

1. **Type Safety**: How these implementations use strong typing to prevent protocol violations
2. **Testing Patterns**: Comprehensive test suites with both unit and integration tests
3. **API Design**: Clean, ergonomic interfaces that hide protocol complexity
4. **Performance**: Efficient implementations with proper connection pooling and multiplexing
5. **Error Handling**: Robust error handling patterns for network and protocol errors

### Implementation Notes

The h2o Crystal shard draws inspiration from these implementations while leveraging Crystal's unique features:
- **Compile-time type checking** for protocol compliance
- **Zero-cost abstractions** for performance
- **Fiber-based concurrency** for efficient multiplexing
- **Memory safety** without garbage collection overhead
