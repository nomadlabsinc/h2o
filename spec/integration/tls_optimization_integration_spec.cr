require "../spec_helper"
require "../../src/h2o"

describe "TLS Optimization Integration" do
  it "demonstrates TLS caching in real HTTP/2 connections" do
    server = HTTP::Server.new do |context|
      context.response.headers["X-Request-Path"] = context.request.path || "/"
      context.response.print("Response for #{context.request.path}")
    end

    address = server.bind_tcp(0)
    port = address.port
    spawn { server.listen }

    sleep 0.1

    # Clear cache before test
    H2O.tls_cache.clear

    # Make multiple requests to the same host
    requests = 50
    client = H2O::Client.new

    start_time = Time.monotonic

    requests.times do |i|
      response = client.get("http://localhost:#{port}/test#{i}")
      response.should_not be_nil
      response.try(&.body).should contain("Response for /test#{i}")
    end

    total_time = Time.monotonic - start_time

    # Get cache statistics
    stats = H2O.tls_cache.statistics

    puts "\n=== TLS Caching Integration Test ==="
    puts "Total requests: #{requests}"
    puts "Total time: #{total_time.total_milliseconds.round(2)}ms"
    puts "Average time per request: #{(total_time.total_milliseconds / requests).round(2)}ms"
    puts "Requests per second: #{(requests / total_time.total_seconds).round(0)}"
    puts "\nCache Statistics:"
    puts "  SNI cache hits: #{stats.sni_hits}"
    puts "  SNI cache misses: #{stats.sni_misses}"
    puts "  SNI hit rate: #{(stats.sni_hit_rate * 100).round(1)}%"

    # Verify SNI caching worked
    stats.sni_hits.should be > 0 if requests > 1

    client.close
    server.close
  end

  it "validates connection reuse with TLS optimizations" do
    server = HTTP::Server.new do |context|
      context.response.headers["X-Connection-ID"] = Random::Secure.hex(8)
      context.response.print("OK")
    end

    address = server.bind_tcp(0)
    port = address.port
    spawn { server.listen }

    sleep 0.1

    # Test connection reuse
    client = H2O::Client.new(connection_pool_size: 1)

    connection_ids = Set(String).new

    10.times do
      response = client.get("http://localhost:#{port}/")
      response.should_not be_nil
      if conn_id = response.try(&.headers["X-Connection-ID"]?)
        connection_ids << conn_id
      end
    end

    puts "\n=== Connection Reuse Test ==="
    puts "Total requests: 10"
    puts "Unique connections: #{connection_ids.size}"
    puts "Connection reuse rate: #{((10 - connection_ids.size) / 10.0 * 100).round(1)}%"

    # With connection pooling, we should see reuse
    connection_ids.size.should be <= 3

    client.close
    server.close
  end
end
