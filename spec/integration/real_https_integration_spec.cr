require "../spec_helper"

describe "H2O Real HTTPS Integration Tests" do
  describe "basic HTTPS connectivity" do
    it "can connect to HTTPS endpoints with proper SSL verification" do
      client = H2O::H2::Client.new("httpbin.org", 443, verify_ssl: true)
      
      headers = {"host" => "httpbin.org"}
      response = client.request("GET", "/get", headers)
      
      response.status.should eq(200)
      response.headers["content-type"]?.should_not be_nil
      client.close
    end

    it "can handle HTTPS requests with custom headers" do
      client = H2O::H2::Client.new("httpbin.org", 443, verify_ssl: true)
      
      headers = {
        "host" => "httpbin.org",
        "user-agent" => "h2o-crystal-client",
        "accept" => "application/json"
      }
      response = client.request("GET", "/headers", headers)
      
      response.status.should eq(200)
      client.close
    end

    it "can perform POST requests over HTTPS" do
      client = H2O::H2::Client.new("httpbin.org", 443, verify_ssl: true)
      
      headers = {
        "host" => "httpbin.org",
        "content-type" => "application/json"
      }
      body = "{\"test\": \"data\"}"
      response = client.request("POST", "/post", headers, body)
      
      response.status.should eq(200)
      client.close
    end
  end

  describe "HTTPS error handling" do
    it "handles connection timeout gracefully" do
      expect_raises(IO::TimeoutError) do
        client = H2O::H2::Client.new("1.2.3.4", 443, connect_timeout: 1.seconds)
        client.request("GET", "/", {"host" => "1.2.3.4"})
      end
    end

    it "handles SSL verification failures" do
      expect_raises(OpenSSL::SSL::Error) do
        # Use self-signed cert endpoint that should fail verification
        client = H2O::H2::Client.new("self-signed.badssl.com", 443, verify_ssl: true)
        client.request("GET", "/", {"host" => "self-signed.badssl.com"})
      end
    end
  end
end