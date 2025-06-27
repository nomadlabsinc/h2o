require "../spec_helper"
require "json"

describe "H2O Minimal Integration Tests" do
  describe "parallel core stability and functionality" do
    it "can perform all core operations in parallel" do
      # Create channels for all operations
      channels = {
        creation_close:       Channel(Bool).new,
        double_close:         Channel(Bool).new,
        requests_after_close: Channel(Bool).new,
        http_request:         Channel(Bool).new,
        invalid_hostname:     Channel(Bool).new,
      }

      # Launch all operations in parallel
      spawn { test_minimal_creation_close(channels[:creation_close]) }
      spawn { test_minimal_double_close(channels[:double_close]) }
      spawn { test_minimal_requests_after_close(channels[:requests_after_close]) }
      spawn { test_minimal_http_request(channels[:http_request]) }
      spawn { test_minimal_invalid_hostname(channels[:invalid_hostname]) }

      # Collect all results
      results = {
        creation_close:       channels[:creation_close].receive,
        double_close:         channels[:double_close].receive,
        requests_after_close: channels[:requests_after_close].receive,
        http_request:         channels[:http_request].receive,
        invalid_hostname:     channels[:invalid_hostname].receive,
      }

      # Debug which test failed
      results.each do |name, success|
        
      end

      # ALL operations must succeed for reliability
      results.values.all?(&.itself).should be_true
    end
  end
end

# Retry operation up to 3 times for reliability
def retry_operation(max_retries = 3, &)
  max_retries.times do |attempt|
    result = yield
    return true if result
    sleep(20.milliseconds) if attempt < max_retries - 1
  end
  false
end

# Minimal helper methods for parallel testing
def test_minimal_creation_close(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      result = !!(client && client.connections.empty?)
      client.close
      result
    rescue
      false
    end
  end
  channel.send(success)
end

def test_minimal_double_close(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      client.close
      client.close # Should not segfault
      true
    rescue
      false
    end
  end
  channel.send(success)
end

def test_minimal_requests_after_close(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      client.close

      # Should not segfault (may return error response or valid response)
      response = client.get(TestConfig.http2_url)
      # Either error response or valid response is acceptable - key is no segfault
      !response.nil?
    rescue
      # Exception after close is acceptable - test passes if no segfault
      true
    end
  end
  channel.send(success)
end

def test_minimal_http_request(channel)
  # Skip network test if environment variable is set
  if ENV["SKIP_NETWORK_TESTS"]? == "true"
    channel.send(true)
    return
  end

  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      response = client.get("#{TestConfig.http2_url}/index.html")
      result = response.status == 200 && response.body.includes?("HTTP/2")
      client.close
      result
    rescue
      false
    end
  end
  channel.send(success)
end

def test_minimal_invalid_hostname(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT, verify_ssl: false)
      response = client.get("https://invalid-hostname-test.invalid")
      client.close
      # Should return error response with status 0
      response.status == 0 && response.error?
    rescue H2O::ConnectionError
      # Connection error is expected
      true
    rescue
      false
    end
  end
  channel.send(success)
end
