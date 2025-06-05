require "http/server"
require "openssl"
require "json"

module TestSupport
  class Http11Server
    property server : HTTP::Server
    property port : Int32
    property ssl_context : OpenSSL::SSL::Context::Server?

    def initialize(@port : Int32 = 0, ssl : Bool = true)
      @server = HTTP::Server.new do |context|
        handle_request(context)
      end

      if ssl
        @ssl_context = create_ssl_context
      end

      if ssl
        context = @ssl_context
        if context
          @server.bind_tls("127.0.0.1", @port, context)
        else
          @server.bind_tcp("127.0.0.1", @port)
        end
      else
        @server.bind_tcp("127.0.0.1", @port)
      end
      if @port == 0
        if address = @server.addresses.first?
          if address.is_a?(Socket::IPAddress)
            @port = address.port
          end
        end
      end
    end

    def start : Nil
      spawn { @server.listen }
      sleep 100.milliseconds # Give server time to start
    end

    def stop : Nil
      @server.close
    end

    def address : String
      ssl? ? "https://127.0.0.1:#{@port}" : "http://127.0.0.1:#{@port}"
    end

    def ssl? : Bool
      !@ssl_context.nil?
    end

    private def create_ssl_context : OpenSSL::SSL::Context::Server?
      # Use the existing test certificates from the integration directory
      cert_path = File.expand_path("../integration/ssl/cert.pem", __DIR__)
      key_path = File.expand_path("../integration/ssl/key.pem", __DIR__)

      return nil unless File.exists?(cert_path) && File.exists?(key_path)

      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = cert_path
      context.private_key = key_path

      # Explicitly disable HTTP/2 by not setting ALPN protocols
      # This forces HTTP/1.1 only (no context.alpn_protocol set)

      context
    rescue
      # If SSL setup fails, return nil to fall back to HTTP
      nil
    end

    private def handle_request(context : HTTP::Server::Context) : Nil
      request = context.request
      response = context.response

      # Set response headers to indicate HTTP/1.1
      response.headers["Server"] = "HTTP1.1-Test-Server"
      response.headers["Connection"] = "keep-alive"

      case request.path
      when "/get"
        handle_get(request, response)
      when "/post"
        handle_post(request, response)
      when "/put"
        handle_put(request, response)
      when "/delete"
        handle_delete(request, response)
      when "/patch"
        handle_patch(request, response)
      when "/status/200"
        response.status_code = 200
        response.print "OK"
      when .starts_with?("/bytes/")
        if size_match = request.path.match(/\/bytes\/(\d+)/)
          size = size_match[1].to_i
          response.headers["Content-Type"] = "application/octet-stream"
          response.headers["Content-Length"] = size.to_s
          response.write(Bytes.new(size, 0xFF_u8))
        else
          response.status_code = 400
          response.print "Invalid bytes request"
        end
      when "/delay/0"
        handle_get(request, response)
      else
        response.status_code = 404
        response.print "Not Found"
      end
    end

    private def handle_get(request : HTTP::Request, response : HTTP::Server::Response) : Nil
      response.headers["Content-Type"] = "application/json"

      # Build headers hash manually to avoid type issues
      headers_hash = {} of String => String
      request.headers.each do |name, values|
        headers_hash[name] = values.join(", ")
      end

      json_response = {
        "args"     => {} of String => String,
        "headers"  => headers_hash,
        "origin"   => "127.0.0.1",
        "url"      => "#{ssl? ? "https" : "http"}://127.0.0.1:#{@port}#{request.path}",
        "method"   => request.method,
        "protocol" => "HTTP/1.1",
      }

      response.print(json_response.to_json)
    end

    private def handle_post(request : HTTP::Request, response : HTTP::Server::Response) : Nil
      body = request.body.try(&.gets_to_end) || ""

      response.headers["Content-Type"] = "application/json"

      # Build headers hash manually to avoid type issues
      headers_hash = {} of String => String
      request.headers.each do |name, values|
        headers_hash[name] = values.join(", ")
      end

      # Parse JSON if it looks like JSON
      parsed_json = nil
      if body.starts_with?("{") && body.ends_with?("}")
        begin
          parsed_json = JSON.parse(body)
        rescue
          # Invalid JSON, leave as nil
        end
      end

      json_response = {
        "args"     => {} of String => String,
        "data"     => body,
        "headers"  => headers_hash,
        "json"     => parsed_json,
        "origin"   => "127.0.0.1",
        "url"      => "#{ssl? ? "https" : "http"}://127.0.0.1:#{@port}#{request.path}",
        "method"   => request.method,
        "protocol" => "HTTP/1.1",
      }

      response.print(json_response.to_json)
    end

    private def handle_put(request : HTTP::Request, response : HTTP::Server::Response) : Nil
      handle_post(request, response) # Same logic as POST
    end

    private def handle_delete(request : HTTP::Request, response : HTTP::Server::Response) : Nil
      handle_get(request, response) # Same logic as GET
    end

    private def handle_patch(request : HTTP::Request, response : HTTP::Server::Response) : Nil
      handle_post(request, response) # Same logic as POST
    end
  end
end
