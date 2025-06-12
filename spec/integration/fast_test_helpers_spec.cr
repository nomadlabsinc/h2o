# Fast test helpers optimized for local Docker infrastructure
require "../spec_helper"
require "../../src/h2o/types"

# Ultra-aggressive timeouts for local servers (≤1s maximum)
def fast_client_timeout : H2O::TimeSpan
  500.milliseconds # Down from 1s - local servers respond in ~10-50ms
end

def ultra_fast_timeout : H2O::TimeSpan
  200.milliseconds # For simple requests - extremely fast
end

# Local test server URLs
def test_base_url
  TestConfig.http2_url
end

def http2_only_url(path = "")
  TestConfig.h2_only_url(path)
end

# Optimized retry logic for local infrastructure
def fast_retry(max_attempts : Int32 = 2, timeout : H2O::TimeSpan = fast_client_timeout, &)
  attempts : Int32 = 0
  last_error : Exception? = nil

  while attempts < max_attempts
    attempts += 1
    begin
      result = yield
      if result
        return result
      else
        last_error = Exception.new("Response was nil")
      end
    rescue ex
      last_error = ex
      if attempts >= max_attempts
        raise ex
      end
      # Very fast retry for local servers - no sleep needed
    end
  end

  raise last_error || Exception.new("Fast retry failed")
end

# Create multiple clients in parallel for concurrent testing
def create_parallel_clients(count : Int32, timeout : H2O::TimeSpan = fast_client_timeout)
  clients : Array(H2O::Client) = Array(H2O::Client).new(count)
  channels : Array(Channel(H2O::Client)) = Array(Channel(H2O::Client)).new(count)

  count.times do |_|
    channel : Channel(H2O::Client) = Channel(H2O::Client).new(1)
    channels << channel

    spawn do
      client : H2O::Client = H2O::Client.new(timeout: timeout, verify_ssl: false)
      channel.send(client)
    end
  end

  # Collect all clients with timeout
  channels.each do |channel|
    select
    when client = channel.receive
      clients << client
    when timeout(timeout)
      raise "Timeout waiting for client creation"
    end
  end

  clients
end

# Parallel request execution
def parallel_requests(urls : H2O::StringArray, client : H2O::Client)
  channels : Array(Channel(H2O::Response?)) = Array(Channel(H2O::Response?)).new(urls.size)

  urls.each do |url|
    channel : Channel(H2O::Response?) = Channel(H2O::Response?).new(1)
    channels << channel

    spawn do
      response : H2O::Response? = fast_retry { client.get(url) }
      channel.send(response)
    end
  end

  # Collect all responses with timeout
  responses : H2O::ResponseArray = Array(H2O::Response?).new(urls.size)
  channels.each do |channel|
    select
    when response = channel.receive
      responses << response
    when timeout(fast_client_timeout)
      responses << nil
    end
  end

  responses
end

# Batch test execution for maximum parallelism
def batch_test(test_count : Int32, &block : Int32 -> Nil)
  channels : Array(Channel(Bool)) = Array(Channel(Bool)).new(test_count)

  test_count.times do |i|
    channel : Channel(Bool) = Channel(Bool).new(1)
    channels << channel

    spawn do
      begin
        block.call(i)
        channel.send(true)
      rescue
        channel.send(false)
      end
    end
  end

  # Wait for all tests to complete with timeout
  results : H2O::BoolArray = channels.map do |channel|
    select
    when result = channel.receive
      result
    when timeout(fast_client_timeout)
      false
    end
  end
  successful_count : Int32 = results.count(&.itself)

  {successful_count, test_count}
end

# Fast validation - just check basic functionality
def fast_validate_response(response : H2O::Response?)
  return false unless response
  return false unless response.status >= 200 && response.status < 600
  return false unless response.protocol == "HTTP/2"
  true
end
