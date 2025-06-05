require "../spec_helper"
require "json"

describe "H2O Real HTTPS Integration Tests" do
  describe "parallel HTTP operations with reliable batching" do
    it "can perform all HTTP operations in optimized parallel batches" do
      # Batch 1: Core httpbin operations (most reliable endpoint)
      httpbin_channels = {
        get:     Channel(Bool).new,
        post:    Channel(Bool).new,
        put:     Channel(Bool).new,
        delete:  Channel(Bool).new,
        head:    Channel(Bool).new,
        options: Channel(Bool).new,
        headers: Channel(Bool).new,
        patch:   Channel(Bool).new,
      }

      # Launch httpbin operations in parallel (same endpoint, spread load)
      spawn { test_httpbin_get_reliable(httpbin_channels[:get]) }
      spawn { test_httpbin_post_reliable(httpbin_channels[:post]) }
      spawn { test_httpbin_put_reliable(httpbin_channels[:put]) }
      spawn { test_httpbin_delete_reliable(httpbin_channels[:delete]) }
      spawn { test_httpbin_head_reliable(httpbin_channels[:head]) }
      spawn { test_httpbin_options_reliable(httpbin_channels[:options]) }
      spawn { test_httpbin_headers_reliable(httpbin_channels[:headers]) }
      spawn { test_httpbin_patch_reliable(httpbin_channels[:patch]) }

      # Collect httpbin results
      httpbin_results = {
        get:     httpbin_channels[:get].receive,
        post:    httpbin_channels[:post].receive,
        put:     httpbin_channels[:put].receive,
        delete:  httpbin_channels[:delete].receive,
        head:    httpbin_channels[:head].receive,
        options: httpbin_channels[:options].receive,
        headers: httpbin_channels[:headers].receive,
        patch:   httpbin_channels[:patch].receive,
      }

      # Batch 2: External services (lower concurrency to avoid overwhelming)
      external_channels = {
        nghttp2: Channel(Bool).new,
        google:  Channel(Bool).new,
        github:  Channel(Bool).new,
      }

      spawn { test_nghttp2_get_reliable(external_channels[:nghttp2]) }
      spawn { test_google_get_reliable(external_channels[:google]) }
      spawn { test_github_api_reliable(external_channels[:github]) }

      # Collect external results
      external_results = {
        nghttp2: external_channels[:nghttp2].receive,
        google:  external_channels[:google].receive,
        github:  external_channels[:github].receive,
      }

      # ALL httpbin operations must succeed (most reliable endpoint)
      httpbin_results[:get].should be_true
      httpbin_results[:post].should be_true
      httpbin_results[:put].should be_true
      httpbin_results[:delete].should be_true
      httpbin_results[:head].should be_true
      httpbin_results[:options].should be_true
      httpbin_results[:headers].should be_true
      httpbin_results[:patch].should be_true

      # All external services should also succeed with 1s timeout
      external_results[:nghttp2].should be_true
      external_results[:google].should be_true
      external_results[:github].should be_true

      # Combine and verify 100% success rate
      all_results = httpbin_results.values + external_results.values
      all_results.all?(&.itself).should be_true
    end
  end

  describe "highly parallel connection operations" do
    it "can perform many operations on shared connections in parallel" do
      # Test with 12 parallel requests for high concurrency
      channels = Array(Channel(Bool)).new(12) { Channel(Bool).new }

      12.times do |i|
        spawn do
          success = retry_operation do
            begin
              client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
              response = client.get("https://httpbin.org/get?parallel=#{i}")
              result = !!(response && response.status == 200 && response.body.includes?("parallel=#{i}"))
              client.close
              result
            rescue
              false
            end
          end
          channels[i].send(success)
        end
      end

      # ALL parallel requests must succeed for reliability
      results = channels.map(&.receive)
      results.all?(&.itself).should be_true
    end

    it "can handle concurrent operations across multiple endpoints" do
      # Mix of different endpoints in parallel for maximum parallelization
      channels = Array(Channel(Bool)).new(15) { Channel(Bool).new }

      # Spawn 15 parallel operations across different endpoints
      spawn { test_httpbin_get_reliable(channels[0]) }
      spawn { test_httpbin_post_reliable(channels[1]) }
      spawn { test_httpbin_put_reliable(channels[2]) }
      spawn { test_httpbin_delete_reliable(channels[3]) }
      spawn { test_httpbin_head_reliable(channels[4]) }
      spawn { reliable_httpbin_multi_test(channels[5], "get", "test1") }
      spawn { reliable_httpbin_multi_test(channels[6], "get", "test2") }
      spawn { reliable_httpbin_multi_test(channels[7], "get", "test3") }
      spawn { test_nghttp2_get_reliable(channels[8]) }
      spawn { test_google_get_reliable(channels[9]) }
      spawn { test_github_api_reliable(channels[10]) }
      spawn { reliable_httpbin_multi_test(channels[11], "get", "test4") }
      spawn { reliable_httpbin_multi_test(channels[12], "get", "test5") }
      spawn { reliable_httpbin_multi_test(channels[13], "get", "test6") }
      spawn { reliable_httpbin_multi_test(channels[14], "get", "test7") }

      # ALL operations must succeed
      results = channels.map(&.receive)
      results.all?(&.itself).should be_true
    end
  end

  describe "fast error handling tests" do
    it "handles all error conditions in parallel" do
      error_channels = {
        invalid_url:        Channel(Bool).new,
        timeout:            Channel(Bool).new,
        nonexistent_domain: Channel(Bool).new,
      }

      spawn { test_invalid_url(error_channels[:invalid_url]) }
      spawn { test_timeout_handling(error_channels[:timeout]) }
      spawn { test_nonexistent_domain(error_channels[:nonexistent_domain]) }

      # All error handling tests should pass
      error_results = {
        invalid_url:        error_channels[:invalid_url].receive,
        timeout:            error_channels[:timeout].receive,
        nonexistent_domain: error_channels[:nonexistent_domain].receive,
      }

      error_results.values.all?(&.itself).should be_true
    end
  end

  describe "connection pooling efficiency" do
    it "validates connection pooling with fast parallel requests" do
      client = H2O::Client.new(connection_pool_size: 3, timeout: TestConfig::CONNECTION_POOLING_TIMEOUT)

      begin
        # Fast parallel requests to test pooling
        channels = Array(Channel(Bool)).new(5) { Channel(Bool).new }

        spawn { test_pooling_request(client, "https://httpbin.org/get?pool=1", channels[0]) }
        spawn { test_pooling_request(client, "https://httpbin.org/get?pool=2", channels[1]) }
        spawn { test_pooling_request(client, "https://httpbin.org/get?pool=3", channels[2]) }
        spawn { test_pooling_request(client, "https://api.github.com/zen", channels[3]) }
        spawn { test_pooling_request(client, "https://www.google.com/", channels[4]) }

        results = channels.map(&.receive)

        # ALL connection pooling requests must succeed
        results.all?(&.itself).should be_true

        # Should have multiple connections but respect pool limit
        client.connections.size.should be >= 1
        client.connections.size.should be <= 3
      ensure
        client.close
      end
    end
  end
end

# Reliable helper methods with retry logic for parallel testing
def test_httpbin_get_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      response = client.get("https://httpbin.org/get")
      result = !!(response && response.status == 200 && response.body.includes?("httpbin.org"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_post_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      headers = H2O::Headers.new
      headers["content-type"] = "application/json"
      data = {"test" => "reliable_post"}.to_json
      response = client.post("https://httpbin.org/post", data, headers)
      result = !!(response && response.status == 200 && response.body.includes?("reliable_post"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_put_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      headers = H2O::Headers.new
      headers["content-type"] = "application/json"
      data = {"method" => "PUT"}.to_json
      response = client.put("https://httpbin.org/put", data, headers)
      result = !!(response && response.status == 200 && response.body.includes?("PUT"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_delete_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      response = client.delete("https://httpbin.org/delete")
      result = !!(response && response.status == 200 && response.body.includes?("delete"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_head_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      response = client.head("https://httpbin.org/status/200")
      result = !!(response && response.status == 200 && response.body.empty?)
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_options_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      response = client.options("https://httpbin.org/")
      result = !!(response && response.status == 200)
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_headers_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      headers = H2O::Headers.new
      headers["x-test-header"] = "reliable-test"
      response = client.get("https://httpbin.org/headers", headers)
      result = !!(response && response.status == 200 && response.body.includes?("reliable-test"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_httpbin_patch_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      headers = H2O::Headers.new
      headers["content-type"] = "application/json"
      data = {"method" => "PATCH"}.to_json
      response = client.patch("https://httpbin.org/patch", data, headers)
      result = !!(response && response.status == 200 && response.body.includes?("PATCH"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_nghttp2_get_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::NGHTTP2_TIMEOUT)
    begin
      response = client.get("https://nghttp2.org/")
      result = !!(response && response.status == 200 && response.body.includes?("nghttp2"))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_google_get_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::GOOGLE_TIMEOUT)
    begin
      response = client.get("https://www.google.com/")
      result = !!(response && response.status == 200 && !response.body.empty?)
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

def test_github_api_reliable(channel)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::GITHUB_API_TIMEOUT)
    begin
      response = client.get("https://api.github.com/zen")
      result = !!(response && response.status == 200)
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

# Retry operation up to 3 times for reliability
def retry_operation(max_retries = 3, &)
  max_retries.times do |attempt|
    result = yield
    return true if result
    sleep(100.milliseconds) if attempt < max_retries - 1 # Small delay between retries
  end
  false
end

# Helper for multiple parallel tests
def reliable_httpbin_multi_test(channel, method, test_id)
  success = retry_operation do
    client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
    begin
      response = client.get("https://httpbin.org/get?#{test_id}=#{method}")
      result = !!(response && response.status == 200 && response.body.includes?(test_id))
      client.close
      result
    rescue
      client.close rescue nil
      false
    end
  end
  channel.send(success)
end

# Original helper methods for backward compatibility
def test_nghttp2_get(channel)
  client = H2O::Client.new(timeout: TestConfig::NGHTTP2_TIMEOUT)
  response = client.get("https://nghttp2.org/")
  success = !!(response && response.status == 200 && response.body.includes?("nghttp2"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_get(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  response = client.get("https://httpbin.org/get")
  success = !!(response && response.status == 200 && response.body.includes?("httpbin.org"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_post(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  headers = H2O::Headers.new
  headers["content-type"] = "application/json"
  data = {"test" => "parallel_post"}.to_json
  response = client.post("https://httpbin.org/post", data, headers)
  success = !!(response && response.status == 200 && response.body.includes?("parallel_post"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_put(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  headers = H2O::Headers.new
  headers["content-type"] = "application/json"
  data = {"method" => "PUT"}.to_json
  response = client.put("https://httpbin.org/put", data, headers)
  success = !!(response && response.status == 200 && response.body.includes?("PUT"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_patch(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  headers = H2O::Headers.new
  headers["content-type"] = "application/json"
  data = {"method" => "PATCH"}.to_json
  response = client.patch("https://httpbin.org/patch", data, headers)
  success = !!(response && response.status == 200 && response.body.includes?("PATCH"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_delete(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  response = client.delete("https://httpbin.org/delete")
  success = !!(response && response.status == 200 && response.body.includes?("delete"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_head(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  response = client.head("https://httpbin.org/status/200")
  success = !!(response && response.status == 200 && response.body.empty?)
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_options(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  response = client.options("https://httpbin.org/")
  success = !!(response && response.status == 200)
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_httpbin_headers(channel)
  client = H2O::Client.new(timeout: TestConfig::HTTPBIN_TIMEOUT)
  headers = H2O::Headers.new
  headers["x-test-header"] = "parallel-test"
  response = client.get("https://httpbin.org/headers", headers)
  success = !!(response && response.status == 200 && response.body.includes?("parallel-test"))
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_google_get(channel)
  client = H2O::Client.new(timeout: TestConfig::GOOGLE_TIMEOUT)
  response = client.get("https://www.google.com/")
  success = !!(response && response.status == 200 && !response.body.empty?)
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_github_api(channel)
  client = H2O::Client.new(timeout: TestConfig::GITHUB_API_TIMEOUT)
  response = client.get("https://api.github.com/zen")
  success = !!(response && response.status == 200)
  client.close
  channel.send(success)
rescue
  channel.send(false)
end

def test_invalid_url(channel)
  client = H2O::Client.new
  begin
    client.get("http://httpbin.org/get")
    channel.send(false) # Should have raised exception
  rescue ArgumentError
    channel.send(true) # Expected exception
  rescue
    channel.send(false) # Wrong exception type
  ensure
    client.close
  end
rescue
  channel.send(false)
end

def test_timeout_handling(channel)
  client = H2O::Client.new(timeout: TestConfig::ERROR_TIMEOUT)
  response = client.get("https://www.google.com/")
  # With 50ms timeout, should return nil
  channel.send(response.nil?)
rescue H2O::ConnectionError
  channel.send(true) # Timeout error is acceptable
rescue
  channel.send(false)
end

def test_nonexistent_domain(channel)
  client = H2O::Client.new(timeout: TestConfig::ERROR_TIMEOUT)
  response = client.get("https://this-does-not-exist-99999.invalid/")
  channel.send(response.nil?)
rescue H2O::ConnectionError
  channel.send(true) # Connection error expected
rescue
  channel.send(false)
end

def test_pooling_request(client, url, channel)
  response = client.get(url)
  success = !!(response && response.status == 200)
  channel.send(success)
rescue
  channel.send(false)
end
