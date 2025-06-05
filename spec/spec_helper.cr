require "spec"
require "../src/h2o"

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
  ERROR_TIMEOUT = 50.milliseconds

  # Default timeout for generic tests
  DEFAULT_TIMEOUT = 1.seconds
end
