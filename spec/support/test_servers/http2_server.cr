#!/usr/bin/env crystal

require "http/server"
require "openssl"
require "json"
require "option_parser"
require "log"

# HTTP/2 test server for integration testing
class HTTP2TestServer
  Log = ::Log.for(self)

  @server : HTTP::Server

  def initialize(@port : Int32 = 84430, @host : String = "0.0.0.0", @ssl_cert_path : String? = nil, @ssl_key_path : String? = nil)
    @server = create_server
  end

  def start
    Log.info { "Starting HTTP/2 test server on #{@host}:#{@port}" }
    if @ssl_cert_path && @ssl_key_path
      context = OpenSSL::SSL::Context::Server.new
      context.certificate_chain = @ssl_cert_path.not_nil!
      context.private_key = @ssl_key_path.not_nil!

      # Enable HTTP/2 via ALPN
      context.alpn_protocol = "h2"

      @server.bind_tls(@host, @port, context)
      Log.info { "HTTPS/HTTP2 server ready with TLS" }
    else
      @server.bind_tcp(@host, @port)
      Log.info { "HTTP/2 server ready (no TLS - for testing)" }
    end

    @server.listen
  end

  def stop
    Log.info { "Stopping HTTP/2 test server" }
    @server.close
  end

  private def create_server
    HTTP::Server.new do |context|
      handle_request(context)
    end
  end

  private def handle_request(context : HTTP::Server::Context)
    setup_response_headers(context.response)
    log_request(context.request)
    route_request(context)
  rescue ex
    handle_error(context, ex)
  end

  private def setup_response_headers(response : HTTP::Server::Response)
    response.headers["Content-Type"] = "application/json"
    response.headers["Server"] = "Crystal-HTTP2-TestServer"
    response.headers["X-Protocol"] = "HTTP/2"
  end

  private def log_request(request : HTTP::Request)
    protocol_version = request.version || "2.0"
    Log.info { "#{request.method} #{request.path} - HTTP/#{protocol_version}" }
  end

  private def route_request(context : HTTP::Server::Context)
    request = context.request
    response = context.response

    case request.path
    when "/health"
      handle_health(response, request)
    when "/headers"
      handle_headers(response, request)
    when "/get"
      handle_get(response, request)
    when "/post"
      handle_post(response, request)
    when "/put"
      handle_put(response, request)
    when "/delete"
      handle_delete(response, request)
    when "/status/200", "/status/201", "/status/404", "/status/500"
      handle_status(response, request)
    when "/reject-h1"
      handle_reject_h1(response, request)
    when .starts_with?("/delay/")
      handle_delay(response, request)
    else
      handle_default(response, request)
    end
  end

  private def handle_health(response, request)
    response.status = HTTP::Status::OK
    response.print({
      status:    "healthy",
      protocol:  "HTTP/2",
      server:    "Crystal HTTP/2 Test Server",
      method:    request.method,
      path:      request.path,
      timestamp: Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_headers(response, request)
    headers_hash = {} of String => String
    request.headers.each do |name, values|
      headers_hash[name] = values.join(", ")
    end

    response.status = HTTP::Status::OK
    response.print({
      headers:  headers_hash,
      protocol: "HTTP/2",
      method:   request.method,
      url:      request.resource,
    }.to_json)
  end

  private def handle_get(response, request)
    response.status = HTTP::Status::OK
    response.print({
      method:    "GET",
      protocol:  "HTTP/2",
      path:      request.path,
      query:     request.query,
      timestamp: Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_post(response, request)
    unless request.method == "POST"
      response.status = HTTP::Status::METHOD_NOT_ALLOWED
      response.print({error: "Method not allowed", allowed: ["POST"]}.to_json)
      return
    end

    body = request.body.try(&.gets_to_end) || ""
    response.status = HTTP::Status::OK
    response.print({
      method:         "POST",
      protocol:       "HTTP/2",
      body:           body,
      content_type:   request.headers["Content-Type"]?,
      content_length: request.headers["Content-Length"]?,
      timestamp:      Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_put(response, request)
    unless request.method == "PUT"
      response.status = HTTP::Status::METHOD_NOT_ALLOWED
      response.print({error: "Method not allowed", allowed: ["PUT"]}.to_json)
      return
    end

    body = request.body.try(&.gets_to_end) || ""
    response.status = HTTP::Status::OK
    response.print({
      method:       "PUT",
      protocol:     "HTTP/2",
      body:         body,
      content_type: request.headers["Content-Type"]?,
      timestamp:    Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_delete(response, request)
    unless request.method == "DELETE"
      response.status = HTTP::Status::METHOD_NOT_ALLOWED
      response.print({error: "Method not allowed", allowed: ["DELETE"]}.to_json)
      return
    end

    response.status = HTTP::Status::OK
    response.print({
      method:    "DELETE",
      protocol:  "HTTP/2",
      path:      request.path,
      timestamp: Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_status(response, request)
    status_code = case request.path
                  when "/status/200" then 200
                  when "/status/201" then 201
                  when "/status/404" then 404
                  when "/status/500" then 500
                  else                    200
                  end

    response.status = HTTP::Status.new(status_code)
    response.print({status: status_code, protocol: "HTTP/2"}.to_json)
  end

  private def handle_reject_h1(response, request)
    response.status = HTTP::Status::OK
    response.print({
      message:               "This endpoint only works with HTTP/2",
      protocol:              "HTTP/2",
      connection_successful: true,
      timestamp:             Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_delay(response, request)
    delay_match = request.path.match(/\/delay\/(\d+)/)
    if delay_match
      delay_seconds = delay_match[1].to_i
      sleep(delay_seconds.seconds)
      response.status = HTTP::Status::OK
      response.print({
        delayed:   delay_seconds,
        protocol:  "HTTP/2",
        timestamp: Time.utc.to_rfc3339,
      }.to_json)
    else
      response.status = HTTP::Status::BAD_REQUEST
      response.print({error: "Invalid delay format"}.to_json)
    end
  end

  private def handle_default(response, request)
    response.status = HTTP::Status::OK
    response.print({
      message:   "HTTP/2 test server",
      protocol:  "HTTP/2",
      method:    request.method,
      path:      request.path,
      timestamp: Time.utc.to_rfc3339,
    }.to_json)
  end

  private def handle_error(context, ex)
    Log.error { "Request handling error: #{ex.message}" }
    context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
    context.response.print({error: "Internal server error", details: ex.message}.to_json)
  end
end

# CLI handling
port = 84430
host = "0.0.0.0"
ssl_cert_path : String? = nil
ssl_key_path : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: http2_server [options]"

  parser.on("-p PORT", "--port=PORT", "Port to listen on (default: 84430)") do |port_arg|
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
server = HTTP2TestServer.new(port, host, ssl_cert_path, ssl_key_path)

Signal::INT.trap do
  puts "\\nShutting down HTTP/2 test server..."
  server.stop
  exit(0)
end

Signal::TERM.trap do
  puts "\\nShutting down HTTP/2 test server..."
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
