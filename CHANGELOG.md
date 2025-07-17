# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2025-01-17

### Added
- **7-Layer SRP Architecture Refactor**: Complete restructuring of the codebase following Single Responsibility Principle
  - Layer 1: HTTP Foundation (core HTTP protocol handling)
  - Layer 2: Connection Management (socket lifecycle and state management)
  - Layer 3: Stream Management (HTTP/2 stream handling and multiplexing)
  - Layer 4: Protocol Negotiation (HTTP/1.1 vs HTTP/2 detection and selection)
  - Layer 5: Request/Response Translation (message format conversion)
  - Layer 6: Client Interface (high-level API and user interactions)
  - Layer 7: Connection Pooling (resource management and optimization)
- **Enhanced Error Handling**: Comprehensive error categorization with retry logic and circuit breaker integration
- **Production-Ready Features**: Circuit breaker patterns, connection health validation, and resource management
- **Named Constants**: Replaced magic numbers with well-documented configuration constants for maintainability

### Fixed
- **TLS Channel Close Errors**: Resolved race conditions in concurrent socket operations that caused "Channel is closed" exceptions
- **Connection Pool Health Checks**: Improved connection validation with configurable thresholds (HEALTHY_SCORE_THRESHOLD, MAX_IDLE_TIME, MAX_CONNECTION_AGE)
- **I/O Optimization Stability**: Temporarily disabled problematic I/O optimizations to ensure reliable HTTP connections
- **Memory Safety**: Enhanced object pooling with validation mechanisms to prevent corruption

### Changed
- **CI/CD Optimization**: Split test suite into parallel jobs for faster feedback
  - Unit tests: ~482 examples targeting ~1:15 runtime (frames, hpack, protocol negotiation)
  - Integration tests: ~72 examples targeting ~1:15 runtime (real network I/O)
  - Total CI time reduced while maintaining comprehensive coverage
- **Code Quality**: Improved semantic naming conventions and removed non-descriptive qualifiers
- **Performance**: Enhanced connection pooling with scoring-based health management

## [0.2.0] - 2025-01-10

### Added
- **I/O Protocol Optimizations**: Zero-copy operations and HPACK presets for improved frame processing
- **Advanced Memory Management**: Object pooling and SIMD enhancement for reduced allocations
- **TLS/Certificate Optimization**: Session caching and SNI enhancement for faster connections
- **Circuit Breaker Pattern**: Built-in circuit breaker support for improved reliability
- **Comprehensive HTTP/2 Optimizations**: Performance improvements addressing critical bottlenecks
- **Security Enhancements**: HPACK vulnerability fixes and CONTINUATION flood protection

### Fixed
- **Critical segmentation fault during client shutdown**: Fixed memory access violation in TLS socket cleanup that occurred when closing HTTP/2 connections. The issue was caused by improper fiber termination and double-free scenarios in OpenSSL cleanup. Resolved by implementing defensive socket closing patterns, non-blocking reader loops with timeouts, and proper channel-based connection timeout handling. This fix ensures stable client shutdown without crashes or hanging.
- **HTTP/2 timeout resolution**: Enhanced type safety and proper timeout handling
- **CVE-2024-27316**: Fixed HTTP/2 CONTINUATION flood vulnerability
- **CVE-2023-44487**: Fixed HTTP/2 Rapid Reset Attack vulnerability
- **HPACK compression bombs**: Protected against dynamic table attacks

### Changed
- **Performance tests now use real measurements**: Updated all performance benchmarks to perform actual measurements instead of simulated results. This provides accurate feedback on optimization effectiveness with realistic expectations for micro-benchmarks.
- **Frame processing pipeline**: Implemented high-performance frame processing with optimized parsing
- **String interning**: Advanced memory management with object pooling for better performance

## [0.1.0] - 2025-01-06

### Added
- Initial release of h2o HTTP/2 client
- Core HTTP/2 implementation with all essential features
- Production-ready codebase with comprehensive testing
- Full documentation and examples
