# CI Test Helper
# Implements patterns from Go/Rust HTTP2 libraries for reliable testing

module CITestHelper
  # Retry configuration
  MAX_RETRIES = ENV.fetch("CI_MAX_RETRIES", "3").to_i
  RETRY_DELAY = ENV.fetch("CI_RETRY_DELAY", "2").to_i.seconds

  # Connection configuration for CI
  CONNECTION_TIMEOUT = ENV.fetch("CI_CONNECTION_TIMEOUT", "30").to_i.seconds
  REQUEST_TIMEOUT    = ENV.fetch("CI_REQUEST_TIMEOUT", "30").to_i.seconds

  # Service URLs
  NGINX_URL   = ENV.fetch("NGINX_URL", TestConfig.http2_url)
  HTTPBIN_URL = ENV.fetch("HTTPBIN_URL", TestConfig.http1_url)

  # Helper method to run tests with retries
  def self.with_retry(description : String, &block)
    attempts = 0
    last_error = nil

    loop do
      attempts += 1

      begin
        return yield
      rescue ex
        last_error = ex

        if attempts < MAX_RETRIES
          STDERR.puts "Attempt #{attempts}/#{MAX_RETRIES} failed for: #{description}"
          STDERR.puts "Error: #{ex.message}"
          STDERR.puts "Retrying in #{RETRY_DELAY.total_seconds}s..."
          sleep RETRY_DELAY
        else
          break
        end
      end
    end

    raise last_error.not_nil!
  end

  # Helper to wait for service availability
  def self.wait_for_service(url : String, timeout : Time::Span = 60.seconds)
    deadline = Time.utc + timeout
    client = HTTP::Client.new(URI.parse(url))
    client.tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE if url.starts_with?("https")

    loop do
      begin
        response = client.get("/")
        return if response.success?
      rescue
        # Ignore connection errors during startup
      end

      if Time.utc > deadline
        raise "Service at #{url} failed to become available after #{timeout.total_seconds}s"
      end

      sleep 1.second
    end
  ensure
    client.try &.close
  end

  # Helper to create isolated test clients
  def self.create_test_client(base_url : String = NGINX_URL) : H2O::Client
    H2O::Client.new.tap do |client|
      client.connection_timeout = CONNECTION_TIMEOUT
      client.read_timeout = REQUEST_TIMEOUT
      client.write_timeout = REQUEST_TIMEOUT

      # Enable debugging in CI
      if ENV["CI"]?
        client.debug = true
      end
    end
  end

  # Helper for parallel test execution
  def self.run_parallel_tests(count : Int32, &block : Int32 ->)
    channel = Channel(Exception?).new(count)

    count.times do |i|
      spawn do
        begin
          yield i
          channel.send(nil)
        rescue ex
          channel.send(ex)
        end
      end
    end

    errors = [] of Exception
    count.times do
      if error = channel.receive
        errors << error
      end
    end

    unless errors.empty?
      raise "#{errors.size} parallel tests failed:\n#{errors.map(&.message).join("\n")}"
    end
  end

  # Helper to ensure clean test state
  def self.with_clean_state(&block)
    # Clear any connection pools
    H2O::Client.clear_all_pools if H2O::Client.responds_to?(:clear_all_pools)

    # Run the test
    yield
  ensure
    # Cleanup after test
    H2O::Client.clear_all_pools if H2O::Client.responds_to?(:clear_all_pools)
  end

  # Performance measurement helper
  def self.measure_performance(description : String, iterations : Int32 = 100, &block)
    times = [] of Time::Span

    iterations.times do
      start = Time.monotonic
      yield
      times << Time.monotonic - start
    end

    avg_time = times.sum / iterations
    min_time = times.min
    max_time = times.max

    puts "Performance: #{description}"
    puts "  Iterations: #{iterations}"
    puts "  Average: #{avg_time.total_milliseconds}ms"
    puts "  Min: #{min_time.total_milliseconds}ms"
    puts "  Max: #{max_time.total_milliseconds}ms"
  end
end

# Spec helper extensions
module Spec
  # Add retry capability to specs
  macro it_with_retry(description, &block)
    it {{description}} do
      CITestHelper.with_retry({{description}}) do
        {{block.body}}
      end
    end
  end

  # Add timeout capability to specs
  macro it_with_timeout(description, timeout, &block)
    it {{description}} do
      channel = Channel(Exception?).new

      spawn do
        begin
          {{block.body}}
          channel.send(nil)
        rescue ex
          channel.send(ex)
        end
      end

      select
      when error = channel.receive
        raise error if error
      when timeout({{timeout}})
        raise "Test '{{description}}' timed out after {{timeout}}"
      end
    end
  end
end
