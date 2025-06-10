require "http/client"
require "openssl"

module H2O
  module H1
    class Client < BaseConnection
      property client : HTTP::Client
      property closed : Bool

      def initialize(hostname : String, port : Int32, connect_timeout : Time::Span = 5.seconds, verify_ssl : Bool = true)
        tls_context = OpenSSL::SSL::Context::Client.new
        tls_context.verify_mode = verify_ssl ? OpenSSL::SSL::VerifyMode::PEER : OpenSSL::SSL::VerifyMode::NONE
        # Force HTTP/1.1 by not setting ALPN or setting it to http/1.1
        @client = HTTP::Client.new(hostname, port, tls: tls_context)
        @client.connect_timeout = connect_timeout
        @client.read_timeout = connect_timeout
        @closed = false
      end

      def request(method : String, path : String, headers : Headers = Headers.new, body : String? = nil) : Response
        return Response.error(0, "Connection is closed", "HTTP/1.1") if @closed

        http_headers = HTTP::Headers.new
        headers.each do |name, value|
          http_headers[name] = value
        end

        begin
          http_response = @client.exec(method, path, http_headers, body)

          response_headers = Headers.new
          http_response.headers.each do |name, values|
            response_headers[name.downcase] = values.join(", ")
          end

          Response.new(
            status: http_response.status_code,
            headers: response_headers,
            body: http_response.body,
            protocol: "HTTP/1.1"
          )
        rescue ex : Exception
          Log.error { "HTTP/1.1 request failed: #{ex.message}" }
          Response.error(0, ex.message.to_s, "HTTP/1.1")
        end
      end

      def close : Nil
        return if @closed
        @closed = true
        @client.close
      end

      def closed? : Bool
        @closed
      end
    end
  end
end
