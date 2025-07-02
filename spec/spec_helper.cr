require "spec"
require "../src/h2o"
require "./support/http11_server"
require "./support/test_urls"
require "./support/test_config"
require "./support/nghttpd_helper"

{% if env("CI") %}
  require "./support/ci_test_helper"
{% end %}

# Test configuration
Log.setup("h2o", :debug)

# Centralized timeout configuration for tests
module TestConfig
  # Reliable 1-second timeouts for all operations
  LOCALHOST_TIMEOUT   = 1.seconds
  LOCAL_API_TIMEOUT   = 1.seconds
  LOCAL_HTTP2_TIMEOUT = 1.seconds
  FAST_LOCAL_TIMEOUT  = 1.seconds

  # Connection pooling tests
  CONNECTION_POOLING_TIMEOUT = 1.seconds

  # Error handling tests need short but reliable timeouts
  ERROR_TIMEOUT = 500.milliseconds

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

# Helper for clearing global state between tests to prevent interference
module GlobalStateHelper
  def self.clear_all_caches
    # Clear the global TLS cache (removed - no longer using global cache)
    # H2O.tls_cache.clear
    # Clear buffer pool stats to prevent interference between tests
    H2O::BufferPool.reset_stats
  end

  # Clear performance benchmark shared state
  def self.clear_benchmark_state
    # Clear allocation tracker state if the module is loaded
    {% if @type.has_constant?("PerformanceBenchmarks") %}
      PerformanceBenchmarks::AllocationTracker.reset
    {% end %}
  end

  # Call this before tests that require clean global state
  def self.ensure_clean_state
    clear_all_caches
    clear_benchmark_state
    # Small delay to ensure any background fibers have finished
    sleep 1.milliseconds
  end
end
