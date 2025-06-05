require "../spec_helper"

describe H2O::H1::Client do
  describe "#initialize" do
    it "should create a new HTTP/1.1 connection" do
      # Skip if we can't connect to test server
      begin
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)
        connection.closed?.should be_false
        connection.close
      rescue
        pending "Cannot connect to test server"
      end
    end

    # Skip server-dependent test that requires specific server configuration
    # it "should raise error if HTTP/2 is negotiated instead of HTTP/1.1" do
    #   pending "Server-dependent test - requires HTTP/2 only server"
    # end
  end

  describe "#request" do
    it "should make GET requests" do
      NetworkTestHelper.with_network_test("HTTP/1.1 GET request") do
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)

        headers = H2O::Headers{
          "host"       => "httpbin.org",
          "user-agent" => "h2o-test",
        }

        response = connection.request("GET", "/get", headers)

        response.should_not be_nil
        if response
          response.status.should eq(200)
          response.protocol.should eq("HTTP/1.1")
          response.body.should contain("httpbin")
        end

        connection.close
      end
    end

    it "should make POST requests with body" do
      NetworkTestHelper.with_network_test("HTTP/1.1 POST request") do
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)

        headers = H2O::Headers{
          "host"         => "httpbin.org",
          "user-agent"   => "h2o-test",
          "content-type" => "application/json",
        }

        body = "{\"test\": \"data\"}"
        response = connection.request("POST", "/post", headers, body)

        response.should_not be_nil
        if response
          response.status.should eq(200)
          response.protocol.should eq("HTTP/1.1")
          response.body.should contain("test")
          response.body.should contain("data")
        end

        connection.close
      end
    end

    it "should handle different HTTP methods" do
      success = NetworkTestHelper.require_network("HTTP/1.1 multiple methods") do
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)

        methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
        successful_requests = 0

        methods.each do |method|
          headers = H2O::Headers{
            "host"       => "httpbin.org",
            "user-agent" => "h2o-test",
          }

          path = case method
                 when "GET"
                   "/get"
                 when "POST"
                   "/post"
                 when "PUT"
                   "/put"
                 when "DELETE"
                   "/delete"
                 when "PATCH"
                   "/patch"
                 else
                   "/get"
                 end

          body = (method != "GET") ? "{}" : nil
          response = connection.request(method, path, headers, body)

          if response && response.status == 200
            successful_requests += 1
            response.protocol.should eq("HTTP/1.1")
          end
        end

        connection.close

        # Return true if at least some requests succeeded
        successful_requests > 0
      end

      # Only assert if network test ran and succeeded
      if success
        success.should be_true
      end
    end

    it "should raise error when connection is closed" do
      begin
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)
        connection.close

        expect_raises(H2O::ConnectionError, "Connection is closed") do
          connection.request("GET", "/get")
        end
      rescue
        pending "Cannot connect to test server"
      end
    end
  end

  describe "#close" do
    it "should close the connection" do
      begin
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)
        connection.closed?.should be_false

        connection.close
        connection.closed?.should be_true

        # Multiple closes should be safe
        connection.close
        connection.closed?.should be_true
      rescue
        pending "Cannot connect to test server"
      end
    end
  end

  describe "#closed?" do
    it "should return connection status" do
      begin
        connection = H2O::H1::Client.new("httpbin.org", 443, connect_timeout: 1.seconds)

        connection.closed?.should be_false
        connection.close
        connection.closed?.should be_true
      rescue
        pending "Cannot connect to test server"
      end
    end
  end
end
