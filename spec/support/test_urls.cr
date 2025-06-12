# Centralized test URLs for CI compatibility
module TestUrls
  # Use 127.0.0.1 instead of localhost to avoid DNS issues in CI
  NGINX_HTTPS_URL = "https://127.0.0.1:8443"
  NGINX_HTTP1_URL = "https://127.0.0.1:8445"
  HTTPBIN_URL     = "http://127.0.0.1:8080"

  # Legacy compatibility
  def self.nginx_url
    NGINX_HTTPS_URL
  end

  def self.http1_url
    NGINX_HTTP1_URL
  end

  def self.httpbin_url
    HTTPBIN_URL
  end
end
