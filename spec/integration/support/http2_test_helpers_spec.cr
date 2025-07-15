require "../../spec_helper"

# Helper methods for HTTP/2 integration tests
module HTTP2TestHelpers
  # Timeout configurations
  def self.ultra_fast_timeout
    500.milliseconds
  end

  def self.fast_timeout
    1.seconds
  end

  def self.standard_timeout
    5.seconds
  end

  # URL helpers
  def self.localhost_url(path : String = "/")
    "http://localhost:8080#{path}"
  end

  def self.http2_url(path : String = "/")
    "#{TestConfig.http2_url}#{path}"
  end

  # Get a test client with sensible defaults
  def self.create_test_client(timeout : Time::Span = standard_timeout)
    H2O::Client.new(
      connection_pool_size: 5,
      timeout: timeout,
      verify_ssl: false
    )
  end

  # Retry helper for flaky network tests
  def self.retry_request(max_attempts : Int32 = 3, acceptable_statuses : Range(Int32, Int32)? = nil, &)
    attempts = 0
    last_error = nil
    last_response = nil
    
    while attempts < max_attempts
      attempts += 1
      begin
        response = yield
        
        # If we have acceptable_statuses defined, check if response status is in range
        if acceptable_statuses && response.is_a?(H2O::Response)
          if acceptable_statuses.includes?(response.status)
            return response
          else
            # Status not in acceptable range, treat as error
            last_response = response
            last_error = Exception.new("Status #{response.status} not in acceptable range #{acceptable_statuses}")
          end
        else
          return response
        end
      rescue ex
        last_error = ex
        sleep 10.milliseconds if attempts < max_attempts
      end
    end
    
    # Return last response if available, otherwise error response
    if last_response
      last_response
    else
      H2O::Response.error(0, last_error.try(&.message) || "Request failed", "HTTP/2")
    end
  end

  # Validation helper
  def self.assert_valid_http2_response(response : H2O::Response, expected_status : Int32? = nil)
    response.should_not be_nil
    
    if expected_status
      response.status.should eq(expected_status)
    else
      response.status.should be >= 200
      response.status.should be < 600
    end
    
    response.protocol.should eq("HTTP/2")
  end
  
  # Additional URL helpers that might be needed
  def self.http2_only_url(path : String = "/")
    "#{TestConfig.http2_url}#{path}"
  end
  
  # Content assertion helper
  def self.assert_response_contains(response : H2O::Response, expected_content : String)
    response.should_not be_nil
    response.body.should_not be_nil
    response.body.to_s.should contain(expected_content)
  end

  # SSL verification failure helper - reduces code duplication
  def self.assert_ssl_verification_failure(host : String = "nghttpd", port : Int32 = 4430)
    expect_raises(H2O::ConnectionError | OpenSSL::SSL::Error) do
      client = H2O::H2::Client.new(host, port, verify_ssl: true)
      client.get("/", {"host" => "#{host}:#{port}"})
    end
  end
end