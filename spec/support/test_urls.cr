# Centralized test URLs for CI compatibility
module TestUrls
  # Use service names for Docker Compose
  NGINX_HTTPS_URL = "https://nghttpd:443"
  HTTPBIN_URL     = "http://httpbin:80"

  # Legacy compatibility
  def self.nginx_url
    NGINX_HTTPS_URL
  end

  def self.httpbin_url
    HTTPBIN_URL
  end
end
