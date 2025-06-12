require "../spec_helper"

describe "H2O::H2::Client timeout configuration integration", tags: "integration" do
  it "accepts both connect_timeout and request_timeout parameters" do
    connect_timeout = 5.seconds
    request_timeout = 15.seconds

    client = H2O::H2::Client.new(
      TestConfig.http2_host,
      TestConfig.http2_port.to_i,
      connect_timeout: connect_timeout,
      request_timeout: request_timeout,
      verify_ssl: false
    )

    client.request_timeout.should eq(request_timeout)
    client.close
  end

  it "uses default values when timeouts not specified" do
    client = H2O::H2::Client.new(TestConfig.http2_host, TestConfig.http2_port.to_i, verify_ssl: false)

    # Default request_timeout should be 5 seconds
    client.request_timeout.should eq(5.seconds)
    client.close
  end

  it "can set different connect and request timeouts" do
    connect_timeout = 3.seconds
    request_timeout = 25.seconds

    client = H2O::H2::Client.new(
      TestConfig.http2_host,
      TestConfig.http2_port.to_i,
      connect_timeout: connect_timeout,
      request_timeout: request_timeout,
      verify_ssl: false
    )

    client.request_timeout.should eq(request_timeout)
    # Note: connect_timeout is used during initialization and not stored as a property
    client.close
  end
end
