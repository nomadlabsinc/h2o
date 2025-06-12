require "../../spec_helper"

# Shared HTTP/2 test infrastructure for modular test organization
module HTTP2TestHelpers
  def self.client_timeout : Time::Span
    1.seconds # Reduced for local servers
  end

  def self.ultra_fast_timeout : Time::Span
    500.milliseconds # For simple local requests
  end

  # Local test server URLs - using HTTPS with embedded servers
  def self.test_base_url
    TestConfig.http2_url
  end

  def self.localhost_url(path = "")
    TestConfig.http2_url(path)
  end

  def self.http2_only_url(path = "")
    TestConfig.h2_only_url(path)
  end

  def self.caddy_url(path = "")
    TestConfig.caddy_url(path)
  end

  # Optimized retry for local servers - much faster
  def self.retry_request(max_attempts = 2, acceptable_statuses = (200..299), &)
    attempts = 0
    last_error = nil

    while attempts < max_attempts
      attempts += 1
      begin
        result = yield
        # Return result if it's successful or acceptable
        if result && acceptable_statuses.includes?(result.status)
          return result
        elsif result
          # Got a response but not acceptable, try again unless it's the last attempt
          if attempts >= max_attempts
            return result
          end
          puts "Attempt #{attempts} failed with status #{result.status}, retrying..."
          sleep(10.milliseconds) # Very fast retry for local servers
        end
      rescue ex
        last_error = ex
        if attempts >= max_attempts
          raise ex
        end
        puts "Attempt #{attempts} failed with error: #{ex.message}, retrying..."
        sleep(20.milliseconds) # Fast retry for local servers
      end
    end

    raise last_error || Exception.new("All attempts failed")
  end

  # Create standardized client for tests
  def self.create_test_client(timeout = client_timeout)
    H2O::Client.new(timeout: timeout, verify_ssl: false)
  end

  # Common assertions for responses (testing H2O client functionality)
  def self.assert_valid_http2_response(response, expected_status = 200)
    response.should_not be_nil
    response.status.should eq(expected_status)
    response.headers.should_not be_empty
  end

  # Common assertions for response content
  def self.assert_response_contains(response, content)
    response.body.should_not be_empty
    response.body.should contain(content)
  end
end
