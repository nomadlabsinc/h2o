require "../spec_helper"

# Note: TLS socket tests moved to integration tests due to network dependency
# The TlsSocket class always attempts to establish a real connection during initialization,
# making it unsuitable for unit testing without mocking infrastructure.
#
# Unit tests for TLS functionality should focus on:
# - Configuration parameter validation
# - Error handling logic
# - Interface contracts
#
# Actual TLS connection behavior is tested in integration tests with real servers.
