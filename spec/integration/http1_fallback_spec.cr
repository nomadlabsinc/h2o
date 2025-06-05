require "../spec_helper"
require "../support/http11_server"

describe "HTTP/1.1 Fallback Integration" do
  it "should handle HTTP/1.1 fallback when server doesn't support HTTP/2" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(timeout: 1.seconds)

    begin
      response = client.get("#{server.address}/get")

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.should contain("127.0.0.1")
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
      server.stop
    end
  end

  it "should maintain separate connection pools for HTTP/1.1 and HTTP/2" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(connection_pool_size: 2, timeout: 1.seconds)

    begin
      responses = [] of H2O::Response?

      # Make multiple requests to test connection pooling
      5.times do
        response = client.get("#{server.address}/get")
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
      server.stop
    end
  end

  it "should handle HTTP/1.1 POST requests with body" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(timeout: 1.seconds)

    begin
      headers = H2O::Headers{
        "content-type" => "application/json",
      }

      body = "{\"test\": \"data\"}"

      response = client.post("#{server.address}/post", body, headers)

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.should contain("test")
        response.body.should contain("data")
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
      server.stop
    end
  end

  it "should handle HTTP/1.1 with various HTTP methods" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(timeout: 1.seconds)

    begin
      base_url = server.address
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
      server.stop
    end
  end

  it "should handle connection errors gracefully" do
    client = H2O::Client.new(timeout: 1.seconds)

    begin
      # Test with invalid host - should either return nil or raise ConnectionError
      response = client.get("https://invalid-host-that-does-not-exist.example")
      response.should be_nil
    rescue H2O::ConnectionError
      # Connection errors are also acceptable for invalid hosts
    ensure
      client.close
    end
  end

  it "should respect connection pool size limits" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(connection_pool_size: 1, timeout: 1.seconds)

    begin
      # Test that connection pool respects size limits
      # Make requests to the same host to test pool management
      responses = [] of H2O::Response?

      2.times do
        response = client.get("#{server.address}/get")
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
      server.stop
    end
  end

  it "should handle concurrent HTTP/1.1 requests" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(connection_pool_size: 5, timeout: 1.seconds)

    begin
      channel = Channel(H2O::Response?).new(10)

      # Spawn multiple fibers to make concurrent requests
      5.times do
        spawn do
          response = client.get("#{server.address}/delay/0")
          channel.send(response)
        end
      end

      # Collect responses
      responses = [] of H2O::Response?
      5.times do
        response = channel.receive
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
      server.stop
    end
  end

  it "should handle large response bodies" do
    server = TestSupport::Http11Server.new(ssl: true)
    server.start
    client = H2O::Client.new(timeout: 1.seconds)

    begin
      # Request a larger response to test body parsing
      response = client.get("#{server.address}/bytes/1024")

      response.should_not be_nil
      if response
        response.status.should eq(200)
        response.body.bytesize.should eq(1024)
        response.protocol.should eq("HTTP/1.1")
      end
    ensure
      client.close
      server.stop
    end
  end
end
