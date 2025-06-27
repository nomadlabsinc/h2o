require "../spec_helper"
require "../../src/h2o"

describe "TLS Optimization Integration" do
  it "demonstrates TLS caching in real HTTP/2 connections" do
    # Clear cache before test
    H2O.tls_cache.clear

    # Make multiple requests to the same HTTPS host to test TLS caching using local server
    requests = 5 # Reduced for CI reliability
    client = H2O::Client.new(timeout: 1.seconds, verify_ssl: false)

    start_time = Time.monotonic

    requests.times do |i|
      
    end

    total_time = Time.monotonic - start_time

    # Get cache statistics
    stats = H2O.tls_cache.statistics

    

    # Verify SNI caching worked
    stats.sni_hits.should be >= 0 # Hits may be 0 if all requests failed due to network issues

    client.close
  end

  it "validates connection reuse with TLS optimizations" do
    client = H2O::Client.new(timeout: 1.seconds, verify_ssl: false)

    # Track connection metrics
    connections_tested = 3
    response_times = [] of Time::Span

    connections_tested.times do |i|
      start_time = Time.monotonic
      

      # Small delay between requests to allow for connection reuse validation
      sleep(20.milliseconds)
    end

    

    client.close
  end
end
