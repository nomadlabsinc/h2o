require "../spec_helper"

describe "HTTP/1.1 Fallback" do
  it "should handle HTTP/1.1 fallback when server doesn't support HTTP/2" do
    client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
    response = client.get("https://httpbin/get")
    response.status.should eq(200)
    response.body.should contain("httpbin.org")
    client.close
  end

  it "should handle HTTP/1.1 POST requests with JSON body" do
    client = H2O::Client.new(timeout: client_timeout, verify_ssl: false)
    headers = H2O::Headers{"Content-Type" => "application/json"}
    body = %({"test": "data", "number": 42})
    response = client.post("https://httpbin/post", body, headers)
    response.status.should eq(200)
    response.body.should contain("httpbin.org")
    response.body.should contain("json")
    client.close
  end
end
