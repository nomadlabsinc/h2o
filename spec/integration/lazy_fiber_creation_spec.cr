require "../spec_helper"

describe "H2O Performance Integration: Lazy Fiber Creation", tags: "integration" do
  it "should not start fibers on client creation" do
    hostname = TestConfig.http2_host
    port = TestConfig.http2_port.to_i

    client = H2O::H2::Client.new(hostname, port, connect_timeout: 1.seconds, verify_ssl: false)

    # Verify fibers are not started yet (main optimization test)
    client.fibers_started.should be_false

    client.close
  end

  it "should start fibers on first request" do
    hostname = TestConfig.http2_host
    port = TestConfig.http2_port.to_i

    client = H2O::H2::Client.new(hostname, port, connect_timeout: 1.seconds, verify_ssl: false)
    client.fibers_started.should be_false

    start_time = Time.monotonic
    response = client.request("GET", "/")
    request_time = Time.monotonic - start_time

    # Fibers should be started after first request
    client.fibers_started.should be_true
    response.should_not be_nil

    client.close
  end
end
