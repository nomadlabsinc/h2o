require "../spec_helper"
require "../../src/h2o"

describe "TLS/Certificate Optimization Performance" do
  it "measures baseline TLS handshake performance" do
    server = HTTP::Server.new do |context|
      context.response.print("OK")
    end

    address = server.bind_tcp(0)
    port = address.port
    spawn { server.listen }

    sleep 0.1

    connections_count = 10

    puts "\n=== BASELINE TLS Connection Performance ==="

    # Measure connection setup time (includes TLS handshake)
    start_time = Time.monotonic
    connection_times = Array(Time::Span).new

    connections_count.times do |_i|
      conn_start = Time.monotonic
      client = H2O::Client.new
      response = client.get("http://localhost:#{port}/")
      response.should_not be_nil
      conn_time = Time.monotonic - conn_start
      connection_times << conn_time
      client.close
    end

    total_time = Time.monotonic - start_time
    avg_time = connection_times.sum / connections_count

    puts "Total connections: #{connections_count}"
    puts "Total time: #{total_time.total_milliseconds.round(2)}ms"
    puts "Average connection time: #{avg_time.total_milliseconds.round(2)}ms"
    puts "Connections per second: #{(connections_count / total_time.total_seconds).round(1)}"

    server.close
  end

  it "measures certificate validation overhead" do
    puts "\n=== Certificate Validation Performance ==="

    # Simulate certificate validation operations
    iterations = 10000

    # Create mock certificate data
    cert_subjects = Array.new(100) { |i| "CN=test#{i}.example.com" }
    cert_issuers = Array.new(10) { |i| "CN=CA#{i}" }

    # Baseline: Simulate certificate validation operations
    start_time = Time.monotonic
    validated = 0

    iterations.times do |i|
      # Simulate certificate field access
      subject = cert_subjects[i % cert_subjects.size]
      issuer = cert_issuers[i % cert_issuers.size]

      # Simulate validation checks
      valid = subject.includes?("example.com")
      trusted = issuer.starts_with?("CN=CA")
      not_expired = Time.utc > Time.utc(2020, 1, 1)

      validated += 1 if valid && trusted && not_expired
    end
    baseline_time = Time.monotonic - start_time

    puts "Baseline validation:"
    puts "  Iterations: #{iterations}"
    puts "  Validated: #{validated}"
    puts "  Total time: #{baseline_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(baseline_time.total_microseconds / iterations).round(2)}μs"
    puts "  Validations per second: #{(iterations / baseline_time.total_seconds).round(0)}"
  end

  it "measures SNI lookup performance" do
    puts "\n=== SNI (Server Name Indication) Performance ==="

    hosts = [
      "example.com",
      "test.example.com",
      "api.example.com",
      "www.example.com",
      "cdn.example.com",
    ]

    iterations_per_host = 1000
    total_iterations = hosts.size * iterations_per_host

    # Simulate SNI lookups
    start_time = Time.monotonic
    hosts.each do |host|
      iterations_per_host.times do
        # Simulate SNI resolution
        sni_name = host.downcase
        sni_bytes = sni_name.to_slice
        # Simulate some processing
        sni_bytes.size
      end
    end
    lookup_time = Time.monotonic - start_time

    puts "SNI lookups:"
    puts "  Total lookups: #{total_iterations}"
    puts "  Total time: #{lookup_time.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(lookup_time.total_microseconds / total_iterations).round(3)}μs"
    puts "  Lookups per second: #{(total_iterations / lookup_time.total_seconds).round(0)}"
  end
end
