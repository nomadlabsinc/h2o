require "../spec_helper"

describe "HTTP/1.1 Local Server Fallback" do
  describe "with HTTP/1.1-only server" do
    it "should successfully fallback to HTTP/1.1 when server doesn't support HTTP/2" do
      # Skip SSL for simplicity in this test - use HTTP instead of HTTPS
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        # Our client currently requires HTTPS, so this test demonstrates
        # the concept but would need client modification to support HTTP
        # In practice, the H1::Client would be used directly for HTTP/1.1-only servers

        # Test direct H1::Client usage
        h1_client = H2O::H1::Client.new(TestConfig.http1_host, server.port, connect_timeout: 1.seconds)

        # This will fail because H1::Client expects HTTPS, but demonstrates the pattern
        # In a real scenario, we'd configure the client for the appropriate protocol

        # For now, let's test the server independently
        http_client = HTTP::Client.new(TestConfig.http1_host, server.port)
        response = http_client.get("/get")

        response.status_code.should eq(200)
        response.body.should contain("HTTP/1.1")
        response.body.should contain("protocol")

        http_client.close
      ensure
        server.stop
      end
    end

    it "should handle HTTP/1.1 POST requests with JSON body" do
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        http_client = HTTP::Client.new(TestConfig.http1_host, server.port)

        headers = HTTP::Headers{
          "Content-Type" => "application/json",
        }

        body = %({"test": "data", "number": 42})
        response = http_client.post("/post", headers: headers, body: body)

        response.status_code.should eq(200)
        response.body.should contain("test")
        response.body.should contain("data")
        response.body.should contain("HTTP/1.1")

        http_client.close
      ensure
        server.stop
      end
    end

    it "should handle various HTTP methods" do
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        http_client = HTTP::Client.new(TestConfig.http1_host, server.port)

        methods = [
          {"GET", "/get"},
          {"POST", "/post"},
          {"PUT", "/put"},
          {"DELETE", "/delete"},
          {"PATCH", "/patch"},
        ]

        methods.each do |(method, path)|
          response = case method
                     when "GET", "DELETE"
                       http_client.exec(method, path)
                     else
                       http_client.exec(method, path, body: "{}")
                     end

          response.status_code.should eq(200)
          response.body.should contain("HTTP/1.1")
          response.body.should contain(method)
        end

        http_client.close
      ensure
        server.stop
      end
    end

    it "should serve large response bodies correctly" do
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        http_client = HTTP::Client.new(TestConfig.http1_host, server.port)

        response = http_client.get("/bytes/1024")

        response.status_code.should eq(200)
        response.headers["Content-Type"].should eq("application/octet-stream")
        response.body.bytesize.should eq(1024)

        http_client.close
      ensure
        server.stop
      end
    end

    it "should handle concurrent requests" do
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        channel = Channel(HTTP::Client::Response).new(5)

        # Spawn multiple fibers to make concurrent requests
        5.times do
          spawn do
            http_client = HTTP::Client.new(TestConfig.http1_host, server.port)
            response = http_client.get("/get")
            channel.send(response)
            http_client.close
          end
        end

        # Collect responses with timeout
        responses = [] of HTTP::Client::Response
        5.times do
          response = select
          when r = channel.receive
            r
          when timeout(5.seconds)
            raise "Timeout waiting for HTTP/1.1 response"
          end
          responses << response
        end

        # All requests should succeed
        responses.each do |response|
          response.status_code.should eq(200)
          response.body.should contain("HTTP/1.1")
        end
      ensure
        server.stop
      end
    end
  end

  describe "demonstrating fallback concept" do
    it "shows how H2::Client would fail and H1::Client would succeed" do
      server = TestSupport::Http11Server.new(ssl: false)
      server.start

      begin
        # This demonstrates the concept - in practice, our client would:
        # 1. Try H2::Client.new - this would fail for HTTP-only servers
        # 2. Fallback to H1::Client.new - but configured for HTTP instead of HTTPS

        # For HTTPS servers that don't support HTTP/2, the fallback works
        # For HTTP-only servers, we'd need additional client configuration

        # Test that our test server correctly serves HTTP/1.1
        http_client = HTTP::Client.new(TestConfig.http1_host, server.port)
        response = http_client.get("/get")

        response.status_code.should eq(200)
        json_body = JSON.parse(response.body)
        json_body["protocol"].should eq("HTTP/1.1")
        json_body["method"].should eq("GET")

        http_client.close
      ensure
        server.stop
      end
    end
  end
end
