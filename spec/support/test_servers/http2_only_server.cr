#!/usr/bin/env crystal

require "http/server"
require "openssl"
require "json"
require "option_parser"
require "log"

# HTTP/2-only test server that rejects HTTP/1.1 connections
class HTTP2OnlyTestServer
  Log = ::Log.for(self)

  @server : HTTP::Server

  def initialize(@port : Int32 = 8447, @host : String = "0.0.0.0", @ssl_cert_path : String? = nil, @ssl_key_path : String? = nil)
    @server = create_server
  end

  def start
    Log.info { "Starting HTTP/2-only test server on #{@host}:#{@port}" }

    unless @ssl_cert_path && @ssl_key_path
      Log.warn { "No SSL certificates provided - HTTP/2 typically requires HTTPS" }
    end

    if @ssl_cert_path && @ssl_key_path
      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = @ssl_cert_path.not_nil!
      context.private_key = @ssl_key_path.not_nil!

      # Force HTTP/2 only via ALPN - reject HTTP/1.1
      context.alpn_protocol = "h2"

      @server.bind_tls(@host, @port, context)
      Log.info { "HTTPS/HTTP2-only server ready with TLS - will reject HTTP/1.1" }
    else
      @server.bind_tcp(@host, @port)
      Log.info { "HTTP/2-only server ready (no TLS - for testing)" }
    end

    @server.listen
  end

  def stop
    Log.info { "Stopping HTTP/2-only test server" }
    @server.close
  end

  private def create_server
    HTTP::Server.new do |context|
      handle_request(context)
    end
  end

  private def handle_request(context : HTTP::Server::Context)
    request = context.request
    response = context.response

    # Check if this is HTTP/1.1 and reject it
    protocol_version = request.version || "2.0"
    if protocol_version == "1.1" || protocol_version == "1.0"
      Log.info { "Rejecting HTTP/#{protocol_version} request from #{request.remote_address}" }
      response.status = HTTP::Status::UPGRADE_REQUIRED
      response.headers["Content-Type"] = "application/json"
      response.headers["Upgrade"] = "h2"
      response.headers["Connection"] = "Upgrade"
      response.print({
        error:             "HTTP/2 Required",
        message:           "This server only accepts HTTP/2 connections",
        protocol_received: "HTTP/#{protocol_version}",
        required_protocol: "HTTP/2.0",
        upgrade_to:        "h2",
      }.to_json)
      return
    end

    # Set headers for HTTP/2 responses
    response.headers["Content-Type"] = "application/json"
    response.headers["Server"] = "Crystal-HTTP2-Only-TestServer"
    response.headers["X-Protocol"] = "HTTP/2"
    response.headers["X-HTTP2-Only"] = "true"

    Log.info { "#{request.method} #{request.path} - HTTP/#{protocol_version} (accepted)" }

    case request.path
    when "/health"
      response.status = HTTP::Status::OK
      response.print({
        status:     "healthy",
        protocol:   "HTTP/2",
        http2_only: true,
        server:     "Crystal HTTP/2-Only Test Server",
        method:     request.method,
        path:       request.path,
        timestamp:  Time.utc.to_rfc3339,
      }.to_json)
    when "/headers"
      headers_hash = {} of String => String
      request.headers.each do |name, values|
        headers_hash[name] = values.join(", ")
      end

      response.status = HTTP::Status::OK
      response.print({
        headers:    headers_hash,
        protocol:   "HTTP/2",
        http2_only: true,
        method:     request.method,
        url:        request.resource,
      }.to_json)
    when "/reject-h1"
      # This endpoint specifically demonstrates HTTP/2-only behavior
      response.status = HTTP::Status::OK
      response.print({
        message:               "This endpoint only works with HTTP/2",
        protocol:              "HTTP/2",
        http2_only:            true,
        connection_successful: true,
        timestamp:             Time.utc.to_rfc3339,
      }.to_json)
    when "/status/200"
      response.status = HTTP::Status::OK
      response.print({
        status:     200,
        protocol:   "HTTP/2",
        http2_only: true,
      }.to_json)
    when "/get"
      response.status = HTTP::Status::OK
      response.print({
        method:     "GET",
        protocol:   "HTTP/2",
        http2_only: true,
        path:       request.path,
        query:      request.query,
        timestamp:  Time.utc.to_rfc3339,
      }.to_json)
    when "/post"
      if request.method == "POST"
        body = request.body.try(&.gets_to_end) || ""
        response.status = HTTP::Status::OK
        response.print({
          method:         "POST",
          protocol:       "HTTP/2",
          http2_only:     true,
          body:           body,
          content_type:   request.headers["Content-Type"]?,
          content_length: request.headers["Content-Length"]?,
          timestamp:      Time.utc.to_rfc3339,
        }.to_json)
      else
        response.status = HTTP::Status::METHOD_NOT_ALLOWED
        response.print({
          error:      "Method not allowed",
          allowed:    ["POST"],
          http2_only: true,
        }.to_json)
      end
    else
      response.status = HTTP::Status::OK
      response.print({
        message:    "HTTP/2-only server - rejects HTTP/1.1",
        protocol:   "HTTP/2",
        http2_only: true,
        method:     request.method,
        path:       request.path,
        timestamp:  Time.utc.to_rfc3339,
      }.to_json)
    end
  rescue ex
    Log.error { "Request handling error: #{ex.message}" }
    context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
    context.response.print({
      error:      "Internal server error",
      details:    ex.message,
      http2_only: true,
    }.to_json)
  end
end

# CLI handling
port = 8447
host = "0.0.0.0"
ssl_cert_path : String? = nil
ssl_key_path : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: http2_only_server [options]"

  parser.on("-p PORT", "--port=PORT", "Port to listen on (default: 8447)") do |port_arg|
    port = port_arg.to_i
  end

  parser.on("-h HOST", "--host=HOST", "Host to bind to (default: 0.0.0.0)") do |host_arg|
    host = host_arg
  end

  parser.on("--cert=PATH", "SSL certificate path") do |path|
    ssl_cert_path = path
  end

  parser.on("--key=PATH", "SSL key path") do |path|
    ssl_key_path = path
  end

  parser.on("--help", "Show this help") do
    puts parser
    exit
  end
end

# Setup graceful shutdown
server = HTTP2OnlyTestServer.new(port, host, ssl_cert_path, ssl_key_path)

Signal::INT.trap do
  puts "\\nShutting down HTTP/2-only test server..."
  server.stop
  exit(0)
end

Signal::TERM.trap do
  puts "\\nShutting down HTTP/2-only test server..."
  server.stop
  exit(0)
end

# Start server
begin
  server.start
rescue ex
  Log.error { "Failed to start server: #{ex.message}" }
  exit(1)
end
