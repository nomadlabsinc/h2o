require "./src/h2o"

# Test H2::Client directly against local nghttpd server with self-signed certificates
Log.setup(:debug)
begin
  puts "Creating H2::Client for local nghttpd server..."
  # Use local nghttpd server with verify_ssl: false for self-signed certificates
  client = H2O::H2::Client.new("localhost", 8443, verify_ssl: false)
  puts "H2::Client created successfully"

  headers = H2O::Headers.new
  headers["host"] = "localhost:8443"

  puts "Sending HTTP/2 request to local server..."
  response = client.request("GET", "/", headers)

  puts "Response status: #{response.status}"
  puts "Response headers: #{response.headers}"
  puts "Response body length: #{response.body.size}"
  puts "Protocol: #{response.protocol}"

  if response.status >= 200 && response.status < 300
    puts "✅ HTTP/2 request successful!"
  else
    puts "❌ HTTP/2 request failed with status #{response.status}"
    puts "Response body preview: #{response.body[0..200]}" if response.body.size > 0
  end

  client.close
rescue ex
  puts "❌ HTTP/2 request failed with exception: #{ex.message}"
  puts ex.backtrace.join("\n")
end
