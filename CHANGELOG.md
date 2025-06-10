# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
