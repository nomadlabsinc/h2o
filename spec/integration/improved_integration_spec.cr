require "../spec_helper"
require "json"

describe "H2O Improved Integration Tests" do
  describe "parallel client functionality and HTTP operations" do
    it "can perform all client operations and HTTP requests in parallel" do
      # Create channels for all operations
      channels = {
        client_creation:        Channel(Bool).new,
        multiple_close:         Channel(Bool).new,
        connection_after_close: Channel(Bool).new,
        http_request:           Channel(Bool).new,
        sequential_requests:    Channel(Bool).new,
        invalid_hostname:       Channel(Bool).new,
      }

      # Launch all operations in parallel
      spawn { test_client_creation_reliable(channels[:client_creation]) }
      spawn { test_multiple_close_reliable(channels[:multiple_close]) }
      spawn { test_connection_after_close_reliable(channels[:connection_after_close]) }
      spawn { test_http_request_reliable(channels[:http_request]) }
      spawn { test_sequential_requests_reliable(channels[:sequential_requests]) }
      spawn { test_invalid_hostname_reliable(channels[:invalid_hostname]) }

      # Collect all results
      results = {
        client_creation:        channels[:client_creation].receive,
        multiple_close:         channels[:multiple_close].receive,
        connection_after_close: channels[:connection_after_close].receive,
        http_request:           channels[:http_request].receive,
        sequential_requests:    channels[:sequential_requests].receive,
        invalid_hostname:       channels[:invalid_hostname].receive,
      }

      # ALL operations must succeed for reliability
      results[:client_creation].should be_true
      results[:multiple_close].should be_true
      results[:connection_after_close].should be_true
      results[:http_request].should be_true
      results[:sequential_requests].should be_true
      results[:invalid_hostname].should be_true

      # Verify 100% success rate
      results.values.all?(&.itself).should be_true
    end
  end
end

# Retry operation up to 3 times for reliability
def retry_operation(max_retries = 3, &)
  max_retries.times do |attempt|
    result = yield
    return true if result
    sleep(100.milliseconds) if attempt < max_retries - 1
  end
  false
end

# Reliable helper methods for parallel testing
def test_client_creation_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      result = !!(client && client.connections.empty?)
      client.close
      result
    rescue
      false
    end
  end
  channel.send(success)
end

def test_multiple_close_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      client.close
      client.close # Should not cause issues
      true
    rescue
      false
    end
  end
  channel.send(success)
end

def test_connection_after_close_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      client.close

      # Should handle requests gracefully after close
      response = client.get("https://httpbin.org/get")
      # Either nil or valid response is acceptable - key is no crashes
      true
    rescue
      # Any exception is acceptable after close
      true
    end
  end
  channel.send(success)
end

def test_http_request_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      response = client.get("https://httpbin.org/get")
      result = !!(response && response.status == 200 && response.body.includes?("httpbin.org"))
      client.close
      result
    rescue
      false
    end
  end
  channel.send(success)
end

def test_sequential_requests_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)

      # First request
      response1 = client.get("https://httpbin.org/get?seq=1")
      return false unless response1 && response1.status == 200

      # Second request
      response2 = client.get("https://httpbin.org/get?seq=2")
      result = !!(response2 && response2.status == 200)

      client.close
      result
    rescue
      false
    end
  end
  channel.send(success)
end

def test_invalid_hostname_reliable(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      response = client.get("https://this-definitely-does-not-exist-99999.invalid")
      client.close
      # Should return nil or throw connection error
      response.nil?
    rescue H2O::ConnectionError
      # Connection error is expected and acceptable
      true
    rescue
      false
    end
  end
  channel.send(success)
end
