# Test configuration using environment variables
# This allows easy swapping of test servers without hardcoding hosts

module TestConfig
  # HTTP/2 test server (nginx)
  def self.http2_host
    ENV["TEST_HTTP2_HOST"]? || "nghttpd"
  end

  def self.http2_port
    ENV["TEST_HTTP2_PORT"]? || "4430"
  end

  def self.http2_url(path = "")
    "https://#{http2_host}:#{http2_port}#{path}"
  end

  # HTTP/1.1 test server (httpbin)
  def self.http1_host
    ENV["TEST_HTTP1_HOST"]? || "httpbin"
  end

  def self.http1_port
    ENV["TEST_HTTP1_PORT"]? || "80"
  end

  def self.http1_url(path = "")
    "http://#{http1_host}:#{http1_port}#{path}"
  end

  # HTTP/2-only server (node.js)
  def self.h2_only_host
    ENV["TEST_H2_ONLY_HOST"]? || "h2-only-server"
  end

  def self.h2_only_port
    ENV["TEST_H2_ONLY_PORT"]? || "8447"
  end

  def self.h2_only_url(path = "")
    "https://#{h2_only_host}:#{h2_only_port}#{path}"
  end

  # Caddy HTTP/2 server
  def self.caddy_host
    ENV["TEST_CADDY_HOST"]? || "caddy-h2"
  end

  def self.caddy_port
    ENV["TEST_CADDY_PORT"]? || "8444"
  end

  def self.caddy_url(path = "")
    "https://#{caddy_host}:#{caddy_port}#{path}"
  end

  # Timeout configurations
  def self.client_timeout
    timeout_ms = ENV["TEST_CLIENT_TIMEOUT_MS"]?.try(&.to_i?) || 5000
    timeout_ms.milliseconds
  end

  def self.fast_timeout
    timeout_ms = ENV["TEST_FAST_TIMEOUT_MS"]?.try(&.to_i?) || 1000
    timeout_ms.milliseconds
  end

  # Debugging
  def self.debug?
    ENV["TEST_DEBUG"]? == "true"
  end

  def self.log_urls
    if debug?
      puts "Test server configuration:"
      puts "  HTTP/2: #{http2_url}"
      puts "  HTTP/1.1: #{http1_url}"
      puts "  H2-only: #{h2_only_url}"
      puts "  Caddy: #{caddy_url}"
    end
  end
end
