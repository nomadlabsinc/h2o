require "../spec_helper"

describe H2O::H1::Client do
  describe "#initialize" do
    it "should create a new HTTP/1.1 connection object" do
      # Test basic object creation (doesn't connect until first request)
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.should_not be_nil
      connection.closed?.should be_false
    end
  end

  describe "#closed?" do
    it "should return false for new connections" do
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.closed?.should be_false
    end

    it "should return true after close" do
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.close
      connection.closed?.should be_true
    end
  end

  describe "#close" do
    it "should mark connection as closed" do
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.closed?.should be_false
      connection.close
      connection.closed?.should be_true
    end

    it "should be idempotent" do
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.close
      connection.close # Should not raise error
      connection.closed?.should be_true
    end
  end

  describe "#request" do
    it "should return error response when connection is closed" do
      connection = H2O::H1::Client.new("example.com", 4430, connect_timeout: 100.milliseconds)
      connection.close

      headers = H2O::Headers{
        "host"       => "example.com",
        "user-agent" => "h2o-test",
      }

      response = connection.request("GET", "/", headers)
      response.should be_a(H2O::Response)
      response.error?.should be_true
      response.status.should eq(0)
      response.error.try(&.includes?("Connection is closed")).should be_true
      response.protocol.should eq("HTTP/1.1")
    end
  end
end
