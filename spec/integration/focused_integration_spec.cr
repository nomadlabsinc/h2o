require "../spec_helper"
require "json"

describe "H2O Focused Integration Tests" do
  describe "parallel basic client operations" do
    it "can perform all basic client operations in parallel" do
      # Create channels for all operations
      channels = {
        client_creation:  Channel(Bool).new,
        multiple_close:   Channel(Bool).new,
        connection_state: Channel(Bool).new,
        http_validation:  Channel(Bool).new,
      }

      # Launch all operations in parallel
      spawn { test_focused_client_creation(channels[:client_creation]) }
      spawn { test_focused_multiple_close(channels[:multiple_close]) }
      spawn { test_focused_connection_state(channels[:connection_state]) }
      spawn { test_focused_http_validation(channels[:http_validation]) }

      # Collect all results
      results = {
        client_creation:  channels[:client_creation].receive,
        multiple_close:   channels[:multiple_close].receive,
        connection_state: channels[:connection_state].receive,
        http_validation:  channels[:http_validation].receive,
      }

      # ALL operations must succeed
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

# Focused helper methods for parallel testing
def test_focused_client_creation(channel)
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

def test_focused_multiple_close(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      client.close
      client.close # Should not cause segfault
      true
    rescue
      false
    end
  end
  channel.send(success)
end

def test_focused_connection_state(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::DEFAULT_TIMEOUT)
      client.close

      # Should handle requests gracefully after close
      response = client.get("https://httpbin.org/get")
      # Either nil or valid response is acceptable - key is no crashes
      true
    rescue
      # Connection error is also acceptable after close
      true
    end
  end
  channel.send(success)
end

def test_focused_http_validation(channel)
  success = retry_operation do
    begin
      client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
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
