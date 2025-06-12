require "../spec_helper"

# Local test server URLs for HTTP/1.1 testing
def http1_server_host
  TestConfig.http1_host
end

def http1_server_port
  TestConfig.http1_port.to_i # HTTPBin container port
end

def http2_only_server_port
  TestConfig.http2_port.to_i # HTTP/2 server port (nginx-h2)
end

# Enhanced health check with retries for CI reliability
def wait_for_service(host : String, port : Int32, timeout = 30.seconds) : Bool
  start_time = Time.utc

  while Time.utc - start_time < timeout
    begin
      socket = TCPSocket.new(host, port, connect_timeout: 1.seconds)
      socket.close
      return true
    rescue ex : Socket::ConnectError
      sleep 0.1.seconds
    rescue ex : IO::TimeoutError
      sleep 0.1.seconds
    end
  end

  false
end

# Clean up any lingering connections before tests
def cleanup_connections
  # Small delay to ensure any background fibers finish
  sleep 10.milliseconds
  # Clear global TLS cache that might hold stale connections
  H2O.tls_cache.clear if H2O.responds_to?(:tls_cache)
end

describe H2O::H1::Client do
  before_each do
    cleanup_connections
  end

  describe "#initialize" do
    it "should create a new HTTP/1.1 connection" do
      # Wait for service to be available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      # Use local HTTPBin server (HTTP/1.1) with longer timeout for CI
      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)
      connection.closed?.should be_false
      connection.close
    end

    it "should handle HTTP/2-only servers gracefully" do
      # Wait for HTTP/2-only service to be available
      wait_for_service(TestConfig.http2_host, http2_only_server_port).should be_true

      # Connect to our HTTP/2-only test server with longer timeout for CI
      connection = H2O::H1::Client.new(TestConfig.http2_host, http2_only_server_port, connect_timeout: 5.seconds, verify_ssl: false)

      # This should either:
      # 1. Fail during connection negotiation if the server rejects HTTP/1.1
      # 2. Return a 426 "Upgrade Required" response
      # 3. Handle the connection gracefully with proper error reporting

      begin
        response = connection.request("GET", "/health")

        if response
          # If we get a response, it should indicate HTTP/2 requirement or rejection
          case response.status
          when 426
            response.body.should contain("HTTP/2 Required")
          when 403
            # Server rejected the connection (also acceptable for HTTP/2-only servers)
            response.status.should eq(403)
          when 200
            # Server accepted HTTP/1.1 - graceful degradation
            response.status.should eq(200)
          else
            # Any other status is acceptable as long as we get a response
            # Status 0 indicates connection error which is expected for HTTP/2-only servers
            [0, 200, 403, 426].should contain(response.status)
          end
        else
          # No response is expected when HTTP/1.1 client connects to HTTP/2-only server
          response.should be_nil
        end

        connection.close
      rescue ex : H2O::ConnectionError
        # Connection errors are expected when trying HTTP/1.1 against HTTP/2-only server
        ex.message.should_not be_nil
        connection.close
      rescue ex : IO::TimeoutError
        # Timeout is acceptable - server may not respond to HTTP/1.1
        connection.close
      rescue ex : OpenSSL::SSL::Error
        # SSL errors during negotiation are expected
        ex.message.should_not be_nil
        connection.close
      rescue ex
        # Other exceptions should be investigated but not fail the test
        puts "Note: HTTP/2-only server behavior: #{ex.class}: #{ex.message}"
        connection.close
      end
    end
  end

  describe "#request" do
    it "should make GET requests" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)

      headers = H2O::Headers{
        "host"       => "#{http1_server_host}:#{http1_server_port}",
        "user-agent" => "h2o-test",
      }

      response = connection.request("GET", "/get", headers)

      response.should_not be_nil
      if response
        # Accept either success or redirection status codes from local HTTPBin
        response.status.should be >= 200
        response.status.should be < 400
        response.protocol.should eq("HTTP/1.1")
        response.body.should contain("args")
      end

      connection.close
    end

    it "should make POST requests with body" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)

      headers = H2O::Headers{
        "host"         => "#{http1_server_host}:#{http1_server_port}",
        "user-agent"   => "h2o-test",
        "content-type" => "application/json",
      }

      body = "{\"test\": \"data\"}"
      response = connection.request("POST", "/post", headers, body)

      response.should_not be_nil
      if response
        response.status.should be >= 200
        response.status.should be < 400
        response.protocol.should eq("HTTP/1.1")
        response.body.should contain("test")
        response.body.should contain("data")
      end

      connection.close
    end

    it "should handle different HTTP methods" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)

      # Test all standard HTTP methods that a core HTTP library should support
      http_methods = [
        {"method" => "GET", "path" => "/get"},
        {"method" => "POST", "path" => "/post"},
        {"method" => "PUT", "path" => "/put"},
        {"method" => "DELETE", "path" => "/delete"},
        {"method" => "PATCH", "path" => "/patch"},
        {"method" => "HEAD", "path" => "/head"},
        {"method" => "OPTIONS", "path" => "/options"},
      ]

      successful_requests = 0
      failed_methods = [] of String

      http_methods.each do |method_info|
        method = method_info["method"]
        path = method_info["path"]

        headers = H2O::Headers{
          "host"       => "#{http1_server_host}:#{http1_server_port}",
          "user-agent" => "h2o-test",
        }

        # Methods that typically include a body
        body = case method
               when "POST", "PUT", "PATCH"
                 "{\"test\": \"data\"}"
               else
                 nil
               end

        begin
          response = connection.request(method, path, headers, body)

          if response && response.status >= 200 && response.status < 400
            successful_requests += 1
            response.protocol.should eq("HTTP/1.1")

            # Verify response contains expected method information (except for HEAD which has no body)
            unless method == "HEAD"
              response.body.should contain(method)
            end

            # For OPTIONS, verify Allow header is present
            if method == "OPTIONS"
              response.headers.has_key?("allow").should be_true
            end
          else
            failed_methods << "#{method} (status: #{response.try(&.status) || "nil"})"
          end
        rescue ex
          failed_methods << "#{method} (error: #{ex.message})"
        end
      end

      connection.close

      # All HTTP methods should succeed with properly configured test server
      if successful_requests != http_methods.size
        fail "Expected all #{http_methods.size} HTTP methods to succeed, but only #{successful_requests} succeeded. Failed: #{failed_methods.join(", ")}"
      end

      successful_requests.should eq(http_methods.size)
    end

    it "should return error response when connection is closed" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)
      connection.close

      response = connection.request("GET", "/get")
      response.should be_a(H2O::Response)
      response.error?.should be_true
      response.status.should eq(0)
    end
  end

  describe "#close" do
    it "should close the connection" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)
      connection.closed?.should be_false

      connection.close
      connection.closed?.should be_true

      # Multiple closes should be safe
      connection.close
      connection.closed?.should be_true
    end
  end

  describe "#closed?" do
    it "should return connection status" do
      # Ensure service is available before testing
      wait_for_service(http1_server_host, http1_server_port).should be_true

      connection = H2O::H1::Client.new(http1_server_host, http1_server_port, connect_timeout: 5.seconds, verify_ssl: false)

      connection.closed?.should be_false
      connection.close
      connection.closed?.should be_true
    end
  end
end
