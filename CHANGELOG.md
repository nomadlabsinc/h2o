# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial implementation of H2O HTTP/2 client for Crystal
- Complete HTTP/2 protocol support (RFC 7540)
- TLS with ALPN negotiation for automatic HTTP/2 detection
- HPACK header compression (RFC 7541) with Huffman encoding
- Full frame parsing and serialization for all HTTP/2 frame types
- Stream multiplexing with proper state management
- Connection and stream-level flow control
- Connection pooling for performance optimization
- Comprehensive error handling and timeout support
- High-performance fiber-based concurrency model
- GitHub Actions CI/CD workflows
- Docker support for development and deployment
- Comprehensive test suite

### Fixed
- **Critical segmentation fault during client shutdown**: Fixed memory access violation in TLS socket cleanup that occurred when closing HTTP/2 connections. The issue was caused by improper fiber termination and double-free scenarios in OpenSSL cleanup. Resolved by implementing defensive socket closing patterns, non-blocking reader loops with timeouts, and proper channel-based connection timeout handling. This fix ensures stable client shutdown without crashes or hanging.

### Changed
- **Performance tests now use real measurements**: Updated all performance benchmarks to perform actual measurements instead of simulated results. This provides accurate feedback on optimization effectiveness with realistic expectations for micro-benchmarks.

## [0.1.0] - 2025-01-06

### Added
- Initial release of h2o HTTP/2 client
- Core HTTP/2 implementation with all essential features
- Production-ready codebase with comprehensive testing
- Full documentation and examples
