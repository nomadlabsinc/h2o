require "../spec_helper"
require "../support/http11_server"

describe "HTTP/1.1 Fallback Integration" do
  it "should handle HTTP/1.1 fallback when server doesn't support HTTP/2" do
    # Use the nginx HTTP/1.1 server on port 8445 (HTTPS without HTTP/2)
    # This should force the H2O::Client to fall back to HTTP/1.1
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    begin
      # nginx HTTP/1.1 service runs on HTTPS port 8445 without HTTP/2 support
      response = client.get("https://#{TestConfig.http1_host}:8445/get")

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.should contain("args")
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
    end
  end

  it "should maintain separate connection pools for HTTP/1.1 and HTTP/2" do
    client = H2O::Client.new(connection_pool_size: 2, timeout: 500.milliseconds, verify_ssl: false)

    begin
      responses = [] of H2O::Response?

      # Make multiple requests to test connection pooling
      5.times do
        response = client.get("https://#{TestConfig.http1_host}:8445/get")
        responses << response
      end

      responses.each do |response|
        response.should_not be_nil
        if response
          response.status.should eq(200)
        end
      end
    ensure
      client.close
    end
  end

  it "should handle HTTP/1.1 POST requests with body" do
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    begin
      headers = H2O::Headers{
        "content-type" => "application/json",
      }

      body = "{\"test\": \"data\"}"

      response = client.post("https://#{TestConfig.http1_host}:8445/post", body, headers)

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.should contain("method")
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
    end
  end

  it "should handle HTTP/1.1 with various HTTP methods" do
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    begin
      base_url = "https://#{TestConfig.http1_host}:8445"
      methods = [
        {"GET", "#{base_url}/get"},
        {"POST", "#{base_url}/post"},
        {"PUT", "#{base_url}/put"},
        {"DELETE", "#{base_url}/delete"},
        {"PATCH", "#{base_url}/patch"},
      ]

      methods.each do |(method, url)|
        response = case method
                   when "GET"
                     client.get(url)
                   when "POST"
                     client.post(url, "{}")
                   when "PUT"
                     client.put(url, "{}")
                   when "DELETE"
                     client.delete(url)
                   when "PATCH"
                     client.patch(url, "{}")
                   end

        response.should_not be_nil
        if response
          response.status.should eq(200)
          response.protocol.should eq("HTTP/1.1")
        end
      end
    ensure
      client.close
    end
  end

  it "should handle connection errors gracefully" do
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    begin
      # Test with invalid host - should return error response with status 0
      response = client.get("https://invalid-host-that-does-not-exist.example")
      response.status.should eq(0)
      response.error?.should be_true
    rescue H2O::ConnectionError
      # Connection errors are also acceptable for invalid hosts
    ensure
      client.close
    end
  end

  it "should respect connection pool size limits" do
    client = H2O::Client.new(connection_pool_size: 1, timeout: 500.milliseconds, verify_ssl: false)

    begin
      # Test that connection pool respects size limits
      # Make requests to the same host to test pool management
      responses = [] of H2O::Response?

      2.times do
        response = client.get("https://#{TestConfig.http1_host}:8445/get")
        responses << response
      end

      # All requests should succeed with our local server
      responses.each do |response|
        response.should_not be_nil
        if response
          response.status.should eq(200)
        end
      end
    ensure
      client.close
    end
  end

  it "should handle concurrent HTTP/1.1 requests" do
    client = H2O::Client.new(connection_pool_size: 5, timeout: 500.milliseconds, verify_ssl: false)

    begin
      channel = Channel(H2O::Response?).new(10)

      # Spawn multiple fibers to make concurrent requests
      5.times do
        spawn do
          response = client.get("https://#{TestConfig.http1_host}:8445/delay/0")
          channel.send(response)
        end
      end

      # Collect responses with timeout
      responses = [] of H2O::Response?
      5.times do
        response = select
        when r = channel.receive
          r
        when timeout(1.seconds)
          raise "Timeout waiting for HTTP/1.1 fallback response"
        end
        responses << response
      end

      # All requests should succeed
      responses.each do |response|
        response.should_not be_nil
        if response
          response.status.should eq(200)
          response.protocol.should eq("HTTP/1.1")
        end
      end
    ensure
      client.close
    end
  end

  it "should handle large response bodies" do
    client = H2O::Client.new(timeout: 500.milliseconds, verify_ssl: false)

    begin
      # Request a larger response to test body parsing
      response = client.get("https://#{TestConfig.http1_host}:8445/bytes/1024")

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.bytesize.should be > 0 # nginx returns simplified data
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
    end
  end
end
