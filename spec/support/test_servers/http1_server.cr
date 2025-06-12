#!/usr/bin/env crystal

require "http/server"
require "json"
require "option_parser"
require "log"

# HTTP/1.1 test server for integration testing
class HTTP1TestServer
  Log = ::Log.for(self)

  @server : HTTP::Server

  def initialize(@port : Int32 = 8080, @host : String = "0.0.0.0")
    @server = HTTP::Server.new do |context|
      handle_request(context)
    end
  end

  def start
    Log.info { "Starting HTTP/1.1 test server on #{@host}:#{@port}" }
    @server.bind_tcp(@host, @port)
    @server.listen
  end

  def stop
    Log.info { "Stopping HTTP/1.1 test server" }
    @server.close
  end

  private def handle_request(context : HTTP::Server::Context)
    request = context.request
    response = context.response

    # Set common headers
    response.headers["Content-Type"] = "application/json"
    response.headers["Server"] = "Crystal-HTTP1-TestServer"
    response.headers["X-Protocol"] = "HTTP/1.1"

    # Log request
    Log.info { "#{request.method} #{request.path} - HTTP/#{request.version}" }

    case request.path
    when "/health", "/get"
      response.status = HTTP::Status::OK
      response.print({
        status:    "healthy",
        protocol:  "HTTP/1.1",
        server:    "Crystal HTTP/1.1 Test Server",
        method:    request.method,
        path:      request.path,
        timestamp: Time.utc.to_rfc3339,
      }.to_json)
    when "/headers"
      headers_hash = {} of String => String
      request.headers.each do |name, values|
        headers_hash[name] = values.join(", ")
      end

      response.status = HTTP::Status::OK
      response.print({
        headers:  headers_hash,
        protocol: "HTTP/1.1",
        method:   request.method,
        url:      request.resource,
      }.to_json)
    when "/post"
      if request.method == "POST"
        body = request.body.try(&.gets_to_end) || ""
        response.status = HTTP::Status::OK
        response.print({
          method:         "POST",
          protocol:       "HTTP/1.1",
          body:           body,
          content_type:   request.headers["Content-Type"]?,
          content_length: request.headers["Content-Length"]?,
          timestamp:      Time.utc.to_rfc3339,
        }.to_json)
      else
        response.status = HTTP::Status::METHOD_NOT_ALLOWED
        response.print({error: "Method not allowed", allowed: ["POST"]}.to_json)
      end
    when "/status/200"
      response.status = HTTP::Status::OK
      response.print({status: 200, protocol: "HTTP/1.1"}.to_json)
    when "/status/404"
      response.status = HTTP::Status::NOT_FOUND
      response.print({status: 404, protocol: "HTTP/1.1"}.to_json)
    when "/status/500"
      response.status = HTTP::Status::INTERNAL_SERVER_ERROR
      response.print({status: 500, protocol: "HTTP/1.1"}.to_json)
    when .starts_with?("/delay/")
      delay_match = request.path.match(/\/delay\/(\d+)/)
      if delay_match
        delay_seconds = delay_match[1].to_i
        sleep(delay_seconds.seconds)
        response.status = HTTP::Status::OK
        response.print({
          delayed:   delay_seconds,
          protocol:  "HTTP/1.1",
          timestamp: Time.utc.to_rfc3339,
        }.to_json)
      else
        response.status = HTTP::Status::BAD_REQUEST
        response.print({error: "Invalid delay format"}.to_json)
      end
    else
      response.status = HTTP::Status::OK
      response.print({
        message:   "HTTP/1.1 test server",
        protocol:  "HTTP/1.1",
        method:    request.method,
        path:      request.path,
        timestamp: Time.utc.to_rfc3339,
      }.to_json)
    end
  rescue ex
    Log.error { "Request handling error: #{ex.message}" }
    context.response.status = HTTP::Status::INTERNAL_SERVER_ERROR
    context.response.print({error: "Internal server error", details: ex.message}.to_json)
  end
end

# CLI handling
port = 8080
host = "0.0.0.0"

OptionParser.parse do |parser|
  parser.banner = "Usage: http1_server [options]"

  parser.on("-p PORT", "--port=PORT", "Port to listen on (default: 8080)") do |port_arg|
    port = port_arg.to_i
  end

  parser.on("-h HOST", "--host=HOST", "Host to bind to (default: 0.0.0.0)") do |host_arg|
    host = host_arg
  end

  parser.on("--help", "Show this help") do
    puts parser
    exit
  end
end

# Setup graceful shutdown
server = HTTP1TestServer.new(port, host)

Signal::INT.trap do
  puts "\\nShutting down HTTP/1.1 test server..."
  server.stop
  exit(0)
end

Signal::TERM.trap do
  puts "\\nShutting down HTTP/1.1 test server..."
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
