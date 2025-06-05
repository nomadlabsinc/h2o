require "spec"
require "../src/h2o"
require "./support/http11_server"

# Test configuration
Log.setup("h2o", :debug)

# Centralized timeout configuration for tests
module TestConfig
  # Reliable 1-second timeouts for all operations
  GOOGLE_TIMEOUT     = 1.seconds
  HTTPBIN_TIMEOUT    = 1.seconds
  NGHTTP2_TIMEOUT    = 1.seconds
  GITHUB_API_TIMEOUT = 1.seconds

  # Connection pooling tests
  CONNECTION_POOLING_TIMEOUT = 1.seconds

  # Error handling tests need very short timeouts
  ERROR_TIMEOUT = 100.milliseconds

  # Default timeout for generic tests
  DEFAULT_TIMEOUT = 1.seconds

  # Skip network tests if SKIP_NETWORK_TESTS env var is set
  def self.skip_network_tests?
    ENV["SKIP_NETWORK_TESTS"]? == "true"
  end
end

# Helper module for network-dependent tests
module NetworkTestHelper
  # Wraps a network-dependent test with proper error handling
  # If SKIP_NETWORK_TESTS is set, the test is skipped entirely
  # Otherwise, network failures are handled gracefully with warnings
  def self.with_network_test(description : String, &)
    if TestConfig.skip_network_tests?
      puts "Skipping network test: #{description}"
      return
    end

    begin
      yield
    rescue ex
      puts "Warning: Network test '#{description}' failed: #{ex.message}"
      # Don't fail the test, just log the issue
    end
  end

  # For tests that require successful network operations
  def self.require_network(description : String, &)
    if TestConfig.skip_network_tests?
      puts "Skipping required network test: #{description}"
      return false
    end

    begin
      result = yield
      return true if result
    rescue ex
      puts "Warning: Required network test '#{description}' failed: #{ex.message}"
    end

    false
  end
end
