require "../spec_helper"
require "../../src/h2o"

describe "TLS/Certificate Optimization - Performance Comparison" do
  it "compares certificate validation with and without caching" do
    puts "\n=== Certificate Validation Caching Performance ==="

    # Create test certificate data
    cert_subjects = Array.new(100) { |i| "CN=test#{i}.example.com" }
    cert_issuers = Array.new(10) { |i| "CN=CA#{i}" }
    cert_data_samples = Array.new(100) do |i|
      Bytes.new(256) { |j| ((i + j) % 256).to_u8 }
    end

    iterations = 10000
    unique_certs = 100

    # Test 1: Without caching (baseline)
    start_time = Time.monotonic
    validated_without_cache = 0

    iterations.times do |i|
      cert_idx = i % unique_certs
      cert_data = cert_data_samples[cert_idx]
      subject = cert_subjects[cert_idx]
      issuer = cert_issuers[cert_idx % cert_issuers.size]
      expires = Time.utc + 1.year

      # Direct validation without cache
      valid = subject.includes?("example.com") && issuer.starts_with?("CN=CA") && Time.utc < expires
      validated_without_cache += 1 if valid
    end

    time_without_cache = Time.monotonic - start_time

    # Test 2: With caching
    H2O.tls_cache.clear
    start_time = Time.monotonic
    validated_with_cache = 0

    iterations.times do |i|
      cert_idx = i % unique_certs
      cert_data = cert_data_samples[cert_idx]
      subject = cert_subjects[cert_idx]
      issuer = cert_issuers[cert_idx % cert_issuers.size]
      expires = Time.utc + 1.year

      # Validation with cache
      valid = H2O::CertValidator.validate_cached(cert_data, subject, issuer, expires)
      validated_with_cache += 1 if valid
    end

    time_with_cache = Time.monotonic - start_time

    # Get cache statistics
    stats = H2O.tls_cache.statistics

    puts "\nWithout caching:"
    puts "  Validations: #{iterations}"
    puts "  Validated: #{validated_without_cache}"
    puts "  Total time: #{time_without_cache.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_without_cache.total_microseconds / iterations).round(2)}μs"

    puts "\nWith caching:"
    puts "  Validations: #{iterations}"
    puts "  Validated: #{validated_with_cache}"
    puts "  Total time: #{time_with_cache.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_with_cache.total_microseconds / iterations).round(2)}μs"
    puts "  Cache hits: #{stats.cert_hits}"
    puts "  Cache misses: #{stats.cert_misses}"
    puts "  Hit rate: #{(stats.cert_hit_rate * 100).round(1)}%"

    # Calculate improvement
    improvement = ((time_without_cache - time_with_cache) / time_without_cache * 100).round(1)
    speedup = (time_without_cache.total_milliseconds / time_with_cache.total_milliseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end

  it "compares SNI lookup with and without caching" do
    puts "\n=== SNI Lookup Caching Performance ==="

    hosts = Array.new(50) { |i| "subdomain#{i}.example.com" }
    iterations = 10000

    # Test 1: Without caching
    start_time = Time.monotonic

    iterations.times do |i|
      host = hosts[i % hosts.size]
      # Simulate SNI resolution with some computation
      sni_name = host.downcase
      # Simulate DNS lookup or other processing
      10.times { sni_name.includes?(".") }
      sni_bytes = sni_name.to_slice
      # Simulate processing
      sni_bytes.size
    end

    time_without_cache = Time.monotonic - start_time

    # Test 2: With caching
    H2O.tls_cache.clear
    start_time = Time.monotonic

    iterations.times do |i|
      host = hosts[i % hosts.size]

      # Use cached SNI lookup
      sni_name = H2O.tls_cache.get_sni(host)
      if sni_name.nil?
        # Cache miss - resolve and cache
        sni_name = host.downcase
        H2O.tls_cache.set_sni(host, sni_name)
      end

      # Use the SNI name
      sni_bytes = sni_name.to_slice
      sni_bytes.size
    end

    time_with_cache = Time.monotonic - start_time

    # Get cache statistics
    stats = H2O.tls_cache.statistics

    puts "\nWithout caching:"
    puts "  Lookups: #{iterations}"
    puts "  Total time: #{time_without_cache.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_without_cache.total_microseconds / iterations).round(3)}μs"

    puts "\nWith caching:"
    puts "  Lookups: #{iterations}"
    puts "  Total time: #{time_with_cache.total_milliseconds.round(2)}ms"
    puts "  Average time: #{(time_with_cache.total_microseconds / iterations).round(3)}μs"
    puts "  Cache hits: #{stats.sni_hits}"
    puts "  Cache misses: #{stats.sni_misses}"
    puts "  Hit rate: #{(stats.sni_hit_rate * 100).round(1)}%"

    # Calculate improvement
    improvement = ((time_without_cache - time_with_cache) / time_without_cache * 100).round(1)
    speedup = (time_without_cache.total_milliseconds / time_with_cache.total_milliseconds).round(2)

    puts "\nImprovement:"
    puts "  Performance gain: #{improvement}%"
    puts "  Speedup factor: #{speedup}x"
  end

  it "measures LRU cache performance characteristics" do
    puts "\n=== LRU Cache Performance ==="

    cache_sizes = [100, 1000, 10000]
    operations_per_test = 100000

    cache_sizes.each do |size|
      cache = H2O::LRUCache(String, String).new(size)

      # Prepare test data
      keys = Array.new(size * 2) { |i| "key#{i}" }
      values = Array.new(size * 2) { |i| "value#{i}" }

      # Measure set performance
      start_time = Time.monotonic
      operations_per_test.times do |i|
        idx = i % keys.size
        cache.set(keys[idx], values[idx])
      end
      set_time = Time.monotonic - start_time

      # Measure get performance (with hits and misses)
      start_time = Time.monotonic
      hits = 0
      operations_per_test.times do |i|
        idx = i % keys.size
        result = cache.get(keys[idx])
        hits += 1 if result
      end
      get_time = Time.monotonic - start_time

      hit_rate = (hits.to_f64 / operations_per_test * 100).round(1)

      puts "\nCache size: #{size}"
      puts "  Set operations: #{operations_per_test}"
      puts "  Set time: #{set_time.total_milliseconds.round(2)}ms"
      puts "  Set ops/sec: #{(operations_per_test / set_time.total_seconds).round(0)}"
      puts "  Get operations: #{operations_per_test}"
      puts "  Get time: #{get_time.total_milliseconds.round(2)}ms"
      puts "  Get ops/sec: #{(operations_per_test / get_time.total_seconds).round(0)}"
      puts "  Hit rate: #{hit_rate}%"
    end
  end
end
